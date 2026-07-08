// =====================================================================
// Network module: VNet + subnets + NSGs + public IPs
// =====================================================================
// Provisions the network foundation for the mTLS passthrough POC:
//   - A virtual network with two dedicated subnets:
//       * snet-appgw  -> Application Gateway (WAF_v2)
//       * snet-apim   -> API Management (Internal VNet mode)
//   - An NSG per subnet with the exact rules each service requires.
//   - Two Standard public IPs (one for App Gateway, one for the APIM
//     control plane, which stv2 requires even in Internal mode).
// =====================================================================

@description('Azure region for all resources.')
param location string

@description('Short prefix applied to resource names.')
param namePrefix string

@description('Deterministic suffix for globally-unique names.')
param suffix string

@description('Tags applied to every resource.')
param tags object

// Address plan -------------------------------------------------------
var vnetAddressSpace = '10.20.0.0/16'
var appGwSubnetPrefix = '10.20.1.0/24'
var apimSubnetPrefix = '10.20.2.0/24'

var vnetName = '${namePrefix}-vnet'
var appGwSubnetName = 'snet-appgw'
var apimSubnetName = 'snet-apim'
var appGwNsgName = '${namePrefix}-appgw-nsg'
var apimNsgName = '${namePrefix}-apim-nsg'
var appGwPublicIpName = '${namePrefix}-appgw-pip'
var apimPublicIpName = '${namePrefix}-apim-pip'

// NSG for the Application Gateway subnet ------------------------------
// App Gateway v2 requires inbound from the GatewayManager service tag on
// ports 65200-65535 for its control plane, plus the public client traffic
// on 443 and the Azure infrastructure load balancer.
resource appGwNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: appGwNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-GatewayManager-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '65200-65535'
        }
      }
      {
        name: 'Allow-Internet-Https-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer-Inbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// NSG for the API Management subnet ----------------------------------
// These are the mandatory rules for API Management stv2 in Internal VNet
// mode, plus an explicit allow for Application Gateway -> APIM on 443.
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: apimNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-APIM-Management-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '3443'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '6390'
        }
      }
      {
        name: 'Allow-AppGateway-To-APIM-Inbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: appGwSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: apimSubnetPrefix
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-Storage-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Storage'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-Sql-Outbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'SQL'
          destinationPortRange: '1433'
        }
      }
      {
        name: 'Allow-KeyVault-Outbound'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureKeyVault'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-EntraId-Outbound'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureActiveDirectory'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-AzureMonitor-Outbound'
        properties: {
          priority: 140
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureMonitor'
          destinationPortRanges: [
            '443'
            '1886'
          ]
        }
      }
    ]
  }
}

// Virtual network with both subnets ----------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: appGwSubnetName
        properties: {
          addressPrefix: appGwSubnetPrefix
          networkSecurityGroup: {
            id: appGwNsg.id
          }
        }
      }
      {
        name: apimSubnetName
        properties: {
          addressPrefix: apimSubnetPrefix
          networkSecurityGroup: {
            id: apimNsg.id
          }
        }
      }
    ]
  }
}

// Public IP for Application Gateway (public entry point) --------------
resource appGwPublicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: appGwPublicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: toLower('${namePrefix}appgw${suffix}')
    }
  }
}

// Public IP for the APIM control plane (required by stv2 Internal mode)-
resource apimPublicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: apimPublicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: toLower('${namePrefix}apim${suffix}')
    }
  }
}

output vnetId string = vnet.id
output appGwSubnetId string = '${vnet.id}/subnets/${appGwSubnetName}'
output apimSubnetId string = '${vnet.id}/subnets/${apimSubnetName}'
output appGwPublicIpId string = appGwPublicIp.id
output appGwPublicIpAddress string = appGwPublicIp.properties.ipAddress
output appGwFqdn string = appGwPublicIp.properties.dnsSettings.fqdn
output apimPublicIpId string = apimPublicIp.id

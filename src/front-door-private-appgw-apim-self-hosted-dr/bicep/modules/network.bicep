@description('Azure region for the virtual networks and network security groups.')
param location string

@description('Short prefix applied to resource names.')
param namePrefix string

@description('Tags applied to every resource.')
param tags object

var azureVnetAddressSpace = '10.10.0.0/16'
var appGatewaySubnetPrefix = '10.10.1.0/24'
var appGatewayPrivateLinkSubnetPrefix = '10.10.2.0/24'
var apimSubnetPrefix = '10.10.3.0/24'
var mockOnPremVnetAddressSpace = '10.20.0.0/16'
var aksSubnetPrefix = '10.20.1.0/24'

var azureVnetName = '${namePrefix}-azure-vnet'
var mockOnPremVnetName = '${namePrefix}-mock-onprem-vnet'
var appGatewaySubnetName = 'snet-appgw'
var appGatewayPrivateLinkSubnetName = 'snet-appgw-private-link'
var apimSubnetName = 'snet-apim'
var aksSubnetName = 'snet-aks'

resource appGatewayNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-appgw-nsg'
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
        name: 'Allow-PrivateLink-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: appGatewayPrivateLinkSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: appGatewaySubnetPrefix
          destinationPortRange: '80'
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

resource apimNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-apim-nsg'
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
        name: 'Allow-AppGateway-Inbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: appGatewaySubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: apimSubnetPrefix
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-SelfHostedGateway-Configuration-Inbound'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: aksSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: apimSubnetPrefix
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-Certificate-Validation-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '80'
        }
      }
      {
        name: 'Allow-Storage-Outbound'
        properties: {
          priority: 110
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
          priority: 120
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
          priority: 130
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
          priority: 140
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
          priority: 150
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
      {
        name: 'Allow-AKS-Backend-Outbound'
        properties: {
          priority: 160
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: apimSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: aksSubnetPrefix
          destinationPortRange: '80'
        }
      }
    ]
  }
}

resource aksNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-aks-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-AzureFrontDoor-To-SelfHostedGateway'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer-Inbound'
        properties: {
          priority: 110
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

resource azureVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: azureVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        azureVnetAddressSpace
      ]
    }
    subnets: [
      {
        name: appGatewaySubnetName
        properties: {
          addressPrefix: appGatewaySubnetPrefix
          networkSecurityGroup: {
            id: appGatewayNsg.id
          }
        }
      }
      {
        name: appGatewayPrivateLinkSubnetName
        properties: {
          addressPrefix: appGatewayPrivateLinkSubnetPrefix
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: apimSubnetName
        properties: {
          addressPrefix: apimSubnetPrefix
          networkSecurityGroup: {
            id: apimNsg.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
              locations: [
                location
              ]
            }
            {
              service: 'Microsoft.Sql'
              locations: [
                location
              ]
            }
            {
              service: 'Microsoft.KeyVault'
              locations: [
                location
              ]
            }
          ]
        }
      }
    ]
  }
}

resource mockOnPremVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: mockOnPremVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        mockOnPremVnetAddressSpace
      ]
    }
    subnets: [
      {
        name: aksSubnetName
        properties: {
          addressPrefix: aksSubnetPrefix
          networkSecurityGroup: {
            id: aksNsg.id
          }
        }
      }
    ]
  }
}

resource appGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${namePrefix}-appgw-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource azureToMockOnPrem 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: 'azure-to-mock-onprem'
  parent: azureVnet
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: mockOnPremVnet.id
    }
  }
}

resource mockOnPremToAzure 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: 'mock-onprem-to-azure'
  parent: mockOnPremVnet
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: azureVnet.id
    }
  }
}

output azureVnetId string = azureVnet.id
output mockOnPremVnetId string = mockOnPremVnet.id
output azureVnetName string = azureVnet.name
output mockOnPremVnetName string = mockOnPremVnet.name
output aksSubnetName string = aksSubnetName
output appGatewaySubnetId string = '${azureVnet.id}/subnets/${appGatewaySubnetName}'
output appGatewayPrivateLinkSubnetId string = '${azureVnet.id}/subnets/${appGatewayPrivateLinkSubnetName}'
output appGatewayPublicIpId string = appGatewayPublicIp.id
output apimSubnetId string = '${azureVnet.id}/subnets/${apimSubnetName}'
output aksSubnetId string = '${mockOnPremVnet.id}/subnets/${aksSubnetName}'
output appGatewaySubnetPrefix string = appGatewaySubnetPrefix
output appGatewayPrivateLinkSubnetPrefix string = appGatewayPrivateLinkSubnetPrefix
output apimSubnetPrefix string = apimSubnetPrefix
output aksSubnetPrefix string = aksSubnetPrefix
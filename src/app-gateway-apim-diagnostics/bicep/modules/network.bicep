// ========================================
// Network Module
// ========================================
// Creates the virtual network with a dedicated subnet for the Application
// Gateway and a Standard public IP (with a DNS label) used as the public
// entry point for the demo.

@description('Location for the network resources.')
param location string

@description('Name of the virtual network.')
param vnetName string

@description('Name of the public IP for the Application Gateway.')
param publicIpName string

@description('DNS label for the public IP. Forms <label>.<region>.cloudapp.azure.com.')
param dnsLabel string

@description('Address space for the virtual network.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for the Application Gateway subnet (must be /24 or larger for v2 SKUs).')
param appGwSubnetPrefix string = '10.0.1.0/24'

@description('Tags to apply to the resources.')
param tags object = {}

var appGwSubnetName = 'appgw-subnet'

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: appGwSubnetName
        properties: {
          addressPrefix: appGwSubnetPrefix
        }
      }
    ]
  }
}

// Standard SKU + Static allocation is required for Application Gateway v2.
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: dnsLabel
    }
  }
}

@description('Resource ID of the virtual network.')
output vnetId string = vnet.id

@description('Resource ID of the Application Gateway subnet.')
output appGwSubnetId string = vnet.properties.subnets[0].id

@description('Resource ID of the public IP.')
output publicIpId string = publicIp.id

@description('Allocated public IP address.')
output publicIpAddress string = publicIp.properties.ipAddress

@description('Fully qualified domain name of the public IP.')
output publicIpFqdn string = publicIp.properties.dnsSettings.fqdn

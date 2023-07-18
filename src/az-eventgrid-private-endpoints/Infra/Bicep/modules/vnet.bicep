@description('The name of the virtual network')
param vnetName string = 'yourVNetName'

@description('The location of the virtual network')
param location string = 'yourLocation'

@description('The address prefix for the virtual network')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('The address prefix for the Bastion subnet')
param bastionSubnetPrefix string = '10.0.1.0/24'

@description('The address prefix for the EventGrid subnet')
param eventGridSubnetPrefix string = '10.0.2.0/24'

@description('The address prefix for the ServiceBus subnet')
param serviceBusSubnetPrefix string = '10.0.3.0/24'

@description('The address prefix for the APIM subnet')
param apimSubnetPrefix string = '10.0.4.0/24'

@description('The address prefix for the LogicApp subnet')
param logicAppSubnetPrefix string = '10.0.5.0/24'

@description('The address prefix for the PrivateEndpoint subnet')
param privateEndpointSubnetPrefix string = '10.0.6.0/24'

resource vnet 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'AzureBastionSubnet' 
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
      {
        name: 'EventGridSubnet'
        properties: {
          addressPrefix: eventGridSubnetPrefix
          privateEndpointNetworkPolicies: 'Enabled' 
          privateLinkServiceNetworkPolicies: 'Enabled' 
        }
      }
      {
        name: 'ServiceBusSubnet'
        properties: {
          addressPrefix: serviceBusSubnetPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'ApimSubnet'
        properties: {
          addressPrefix: apimSubnetPrefix
          privateEndpointNetworkPolicies: 'Enabled' 
          privateLinkServiceNetworkPolicies: 'Enabled' 
        }
      }
      {
        name: 'LogicAppSubnet'
        properties: {
          addressPrefix: logicAppSubnetPrefix
          serviceEndpoints: [
            {
              service: 'Microsoft.Web'
            }
          ]
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Enabled' 
          privateLinkServiceNetworkPolicies: 'Enabled' 
        }
      }
      {
        name: 'PrivateEndpointSubnet'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled' 
          privateLinkServiceNetworkPolicies: 'Disabled' 
        }
      }
    ]
  }
}

output bastionSubnetId string = vnet.properties.subnets[0].id
output eventGridSubnetId string = vnet.properties.subnets[1].id
output serviceBusSubnetId string = vnet.properties.subnets[2].id
output apimSubnetId string = vnet.properties.subnets[3].id
output logicAppSubnetId string = vnet.properties.subnets[4].id
output privateEndpointSubnetId string = vnet.properties.subnets[5].id

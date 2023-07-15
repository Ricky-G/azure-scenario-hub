@description('The name of the Event Grid topic')
param eventGridTopicName string

@description('The location of the Event Grid topic')
param location string

@description('The name of the virtual network')
param vnetName string

@description('The name of the subnet for the Private Endpoint of the Event Grid topic')
param privateEndpointSubnetName string

@description('The name of the Private Endpoint for the Event Grid topic')
param privateEndpointName string

resource eventGridTopic 'Microsoft.EventGrid/topics@2022-06-15' = {
  name: eventGridTopicName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2020-07-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, privateEndpointSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'EventGridTopicPrivateLinkConnection'
        properties: {
          privateLinkServiceId: eventGridTopic.id
          groupIds: [
            'topic'
          ]
        }
      }
    ]
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.eventgrid.azure.net'
  location: 'global'
}

resource virtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${privateDnsZone.name}/${vnetName}-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: resourceId('Microsoft.Network/virtualNetworks', vnetName)
    }
    registrationEnabled: true
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-07-01' = {
  name: '${privateEndpoint.name}/default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'EventGridPrivateLinkConfig'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

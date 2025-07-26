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

resource eventGridTopic 'Microsoft.EventGrid/topics@2020-06-01' = {
  name: eventGridTopicName
  location: location
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
        name: '${eventGridTopicName}PrivateLinkConnection'
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

output eventGridTopidPrivateEndpointName string = privateEndpoint.name
output eventGridTopicPrivateEndpointId string = privateEndpoint.id
output eventGridTopicName string = eventGridTopic.name

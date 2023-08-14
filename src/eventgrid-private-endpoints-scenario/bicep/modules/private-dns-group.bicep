@description('The name of the Private Endpoint')
param privateEndpointName string

@description('The ID of the Private DNS Zone')
param privateDnsZoneId string

@description('The name of the Private DNS Zone configuration')
param privateDnsZoneConfigName string

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-07-01' = {
  name: '${privateEndpointName}/default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: privateDnsZoneConfigName
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

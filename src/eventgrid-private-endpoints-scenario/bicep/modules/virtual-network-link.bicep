@description('The name of the Private DNS Zone')
param privateDnsZoneName string

@description('The name of the Virtual Network')
param vnetName string

resource virtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${privateDnsZoneName}/${vnetName}-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: resourceId('Microsoft.Network/virtualNetworks', vnetName)
    }
    registrationEnabled: true
  }
}

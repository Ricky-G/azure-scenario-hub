@description('The name of the Bastion host')
param bastionHostName string

@description('The location of the Bastion host')
param location string

@description('The ID of the Bastion subnet')
param bastionSubnetId string

resource publicIp 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: '${bastionHostName}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2021-02-01' = {
  name: bastionHostName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

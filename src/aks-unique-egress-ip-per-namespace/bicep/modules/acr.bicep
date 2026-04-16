@description('Azure region for the ACR.')
param location string

@description('Short prefix for the ACR name.')
param namePrefix string

@description('Tags to apply to the ACR.')
param tags object

// ACR names must be globally unique, alphanumeric only
var acrName = '${namePrefix}acr${uniqueString(resourceGroup().id)}'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

@description('The name of the ACR.')
output acrName string = acr.name

@description('The login server of the ACR.')
output acrLoginServer string = acr.properties.loginServer

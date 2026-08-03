@description('Azure region for the API Management service.')
param location string

@description('Globally unique name of the API Management service.')
@minLength(1)
@maxLength(50)
param apimServiceName string

@description('Email address shown as the API publisher contact.')
param publisherEmail string

@description('Organization shown as the API publisher.')
param publisherName string

@description('Tags applied to the API Management service.')
param tags object

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimServiceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Premium'
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

@description('Resource ID of the API Management service.')
output id string = apimService.id

@description('Name of the API Management service.')
output name string = apimService.name

@description('Default service gateway URL. Classic Premium workspaces use their workspace gateway URLs instead.')
output gatewayUrl string = apimService.properties.gatewayUrl

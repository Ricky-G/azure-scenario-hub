@description('Azure region for the APIM service.')
param location string

@description('Globally unique APIM service name.')
param apimName string

@description('Publisher email required by API Management.')
param publisherEmail string

@description('Maximum requests per APIM subscription per 60 seconds.')
param callsPerMinute int

@description('Create-only secret APIM named value definitions for backend credentials.')
param backendSecrets array

@description('Tags for the APIM service.')
param tags object

@onlyIfNotExists()
resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: 'Azure Scenario Hub'
    publicNetworkAccess: 'Enabled'
  }
}

@onlyIfNotExists()
resource backendNamedValues 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = [for backendSecret in backendSecrets: {
  parent: apim
  name: backendSecret.name
  properties: {
    displayName: backendSecret.name
    secret: true
    value: backendSecret.placeholder
  }
}]

resource servicePolicy 'Microsoft.ApiManagement/service/policies@2024-05-01' = {
  parent: apim
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: replace(loadTextContent('../../policies/service.xml'), '__CALLS_PER_MINUTE__', string(callsPerMinute))
  }
}

resource product 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apim
  name: 'ai-gateway-poc'
  properties: {
    displayName: 'AI Gateway POC'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource demoSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: 'gateway-demo'
  properties: {
    displayName: 'AI Gateway POC demo'
    scope: product.id
    state: 'active'
  }
}

output apimName string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output subscriptionName string = demoSubscription.name
output productName string = product.name

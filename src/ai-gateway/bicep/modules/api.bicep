@description('Existing APIM service name.')
param apimName string

@description('Existing APIM product name that grants access to this API.')
param productName string

@description('APIM API resource name.')
param apiName string

@description('API display name in the APIM portal.')
param apiDisplayName string

@description('Public APIM URL path prefix.')
param apiPath string

@description('Backend service base URL, without an ending slash.')
param backendUrl string

@description('OpenAPI 3 specification content.')
param spec string

@description('Optional API-level policy XML; empty to inherit only the service policy.')
param policyXml string = ''

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource product 'Microsoft.ApiManagement/service/products@2024-05-01' existing = {
  parent: apim
  name: productName
}

resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: apiName
  properties: {
    displayName: apiDisplayName
    path: apiPath
    protocols: [
      'https'
    ]
    serviceUrl: endsWith(backendUrl, '/') ? substring(backendUrl, 0, max(length(backendUrl) - 1, 0)) : backendUrl
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'subscription-key'
    }
    format: 'openapi'
    value: spec
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = if (!empty(policyXml)) {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: policyXml
  }
}

resource productApi 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: product
  name: api.name
}

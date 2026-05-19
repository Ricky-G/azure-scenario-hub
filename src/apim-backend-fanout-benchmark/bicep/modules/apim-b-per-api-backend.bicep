// ========================================
// APIM-B: one-backend-per-API pattern
// ========================================
// apiCount Backend entities (each pointing at the same Function App but with
// the full path baked into the backend URL) + apiCount APIs (1:1 mapping).
// Each API uses the trivial passthrough fragment so the policy-evaluation cost
// stays equivalent to APIM-A.

@description('Name of the APIM service to configure')
param apimServiceName string

@description('Hostname of the mock backend Function App (no scheme)')
param backendHostname string

@description('Number of APIs / backends to create')
param apiCount int = 10

var passthroughFragmentId = 'per-api-passthrough'

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apimServiceName
}

@batchSize(1)
resource backends 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = [for i in range(1, apiCount): {
  parent: apim
  name: 'mock-backend-${padLeft(i, 2, '0')}'
  properties: {
    protocol: 'http'
    url: 'https://${backendHostname}/api/echo/svc${padLeft(i, 2, '0')}/v1'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}]

resource passthroughFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apim
  name: passthroughFragmentId
  properties: {
    description: 'Trivial passthrough fragment (kept for fairness with APIM-A)'
    format: 'rawxml'
    value: loadTextContent('policy-fragments/per-api-passthrough.xml')
  }
}

@batchSize(1)
resource apis 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = [for i in range(1, apiCount): {
  parent: apim
  name: 'api-perapi-${padLeft(i, 2, '0')}'
  properties: {
    displayName: 'Per-API Backend API ${padLeft(i, 2, '0')}'
    path: 'svc${padLeft(i, 2, '0')}/v1'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    serviceUrl: 'https://${backendHostname}/api/echo/svc${padLeft(i, 2, '0')}/v1'
  }
}]

@batchSize(1)
resource apiOperations 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = [for i in range(1, apiCount): {
  parent: apis[i - 1]
  name: 'get-resource'
  properties: {
    displayName: 'Get Resource'
    method: 'GET'
    urlTemplate: '/resource/{id}'
    templateParameters: [
      {
        name: 'id'
        required: true
        type: 'string'
      }
    ]
  }
}]

@batchSize(1)
resource apiPolicies 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = [for i in range(1, apiCount): {
  parent: apis[i - 1]
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><base /><set-backend-service backend-id="mock-backend-${padLeft(i, 2, '0')}" /><include-fragment fragment-id="${passthroughFragmentId}" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
  dependsOn: [
    backends[i - 1]
    passthroughFragment
    apiOperations[i - 1]
  ]
}]

// ========================================
// APIM-A: shared-backend + rewrite-uri pattern
// ========================================
// 1 Backend entity + apiCount APIs, every API uses the same policy fragment
// (set-backend-service + rewrite-uri) to route to a single shared backend.

@description('Name of the APIM service to configure')
param apimServiceName string

@description('Hostname of the mock backend Function App (no scheme)')
param backendHostname string

@description('Number of APIs to create')
param apiCount int = 10

var sharedBackendId = 'shared-mock-backend'
var rewriteFragmentId = 'shared-backend-rewrite'

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apimServiceName
}

// Single shared backend entity. URL deliberately ends at /api/echo — the
// "rooted" path the customer wants the backend to live behind.
resource sharedBackend 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  parent: apim
  name: sharedBackendId
  properties: {
    protocol: 'http'
    url: 'https://${backendHostname}/api/echo'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

// Policy fragment shared by every API on APIM-A.
resource rewriteFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apim
  name: rewriteFragmentId
  properties: {
    description: 'Routes to shared backend and reconstructs the original path'
    format: 'rawxml'
    value: loadTextContent('policy-fragments/shared-backend-rewrite.xml')
  }
  dependsOn: [
    sharedBackend
  ]
}

// 10 APIs, one operation each. apiIndex is 1-based.
// @batchSize(1) forces serial creation — APIM rejects concurrent API mutations
// with an opaque BadRequest, especially on a freshly-provisioned instance.
@batchSize(1)
resource apis 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = [for i in range(1, apiCount): {
  parent: apim
  name: 'api-shared-${padLeft(i, 2, '0')}'
  properties: {
    displayName: 'Shared Backend API ${padLeft(i, 2, '0')}'
    path: 'svc${padLeft(i, 2, '0')}/v1'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    serviceUrl: 'https://${backendHostname}/api/echo'
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

// API-scope policy that simply invokes the shared fragment.
@batchSize(1)
resource apiPolicies 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = [for i in range(1, apiCount): {
  parent: apis[i - 1]
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><base /><include-fragment fragment-id="${rewriteFragmentId}" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
  dependsOn: [
    rewriteFragment
    apiOperations[i - 1]
  ]
}]

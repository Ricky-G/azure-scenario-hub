// ============================================================================
// Module: apim-service-policy.bicep
// Applies a service-level (global) policy to the APIM instance. Currently
// adds CORS so browser-based demos can call the gateway directly.
// ============================================================================

@description('Existing APIM service name.')
param apimServiceName string

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apimServiceName
}

resource servicePolicy 'Microsoft.ApiManagement/service/policies@2023-05-01-preview' = {
  parent: apim
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../../policies/service-policy.xml')
  }
}

// ============================================================================
// Module: apim-fragments.bicep
// Creates the policy fragments shared by all APIs on this APIM service.
// Idempotent and only run once.
// ============================================================================

@description('Existing APIM service name.')
param apimServiceName string

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apimServiceName
}

resource fragOpenAiUsage 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apim
  name: 'ai-gateway-openai-usage'
  properties: {
    description: 'Captures OpenAI token usage as a structured trace.'
    format: 'rawxml'
    value: loadTextContent('../../policies/frag-openai-usage.xml')
  }
}

resource fragThrottlingEvents 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apim
  name: 'ai-gateway-throttling-events'
  properties: {
    description: 'Captures 429 throttling events as warning traces.'
    format: 'rawxml'
    value: loadTextContent('../../policies/frag-throttling-events.xml')
  }
}

resource fragCacheLookup 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apim
  name: 'ai-gateway-cache-lookup'
  properties: {
    description: 'Body-hash response cache lookup; short-circuits on HIT.'
    format: 'rawxml'
    value: loadTextContent('../../policies/frag-cache-lookup.xml')
  }
}

resource fragCacheStore 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apim
  name: 'ai-gateway-cache-store'
  properties: {
    description: 'Persists successful non-streaming responses for 5 minutes.'
    format: 'rawxml'
    value: loadTextContent('../../policies/frag-cache-store.xml')
  }
}

resource fragMockFallback 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apim
  name: 'ai-gateway-mock-fallback'
  properties: {
    description: 'Returns a graceful 503 mock response when the backend pool fails.'
    format: 'rawxml'
    value: loadTextContent('../../policies/frag-mock-fallback.xml')
  }
}

output fragmentNames array = [
  fragOpenAiUsage.name
  fragThrottlingEvents.name
  fragCacheLookup.name
  fragCacheStore.name
  fragMockFallback.name
]

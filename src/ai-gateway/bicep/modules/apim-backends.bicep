// ============================================================================
// Module: apim-backends.bicep
// Creates two backends pointing at the same Foundry endpoint and a backend
// POOL (priority-based routing with automatic failover) that the AI Gateway
// APIs use as their `set-backend-service` target.
//
// In production the secondary backend would point at a paired-region Foundry
// (e.g. another regional deployment) for true active/passive failover. For
// this single-Foundry demo both members share the same URL and the pool +
// circuit breaker still demonstrate APIM's failover behaviour.
// ============================================================================

@description('Existing APIM service name.')
param apimServiceName string

@description('Public endpoint of the Foundry / Azure OpenAI account.')
param openAiEndpoint string

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

// Strip a single trailing slash so we can safely use the endpoint as a base.
// Backend URL is the FOUNDRY ROOT (no `/openai` suffix). With the API
// operation templates including `/openai/deployments/...`, APIM strips the
// API path and appends `/openai/deployments/...` to this base, hitting the
// canonical Foundry route.
var sanitizedEndpoint = endsWith(openAiEndpoint, '/')
  ? substring(openAiEndpoint, 0, max(length(openAiEndpoint) - 1, 0))
  : openAiEndpoint
var backendUrl = sanitizedEndpoint

resource backendPrimary 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'openai-backend-primary'
  properties: {
    description: 'Primary Foundry / Azure OpenAI backend.'
    type: 'Single'
    url: backendUrl
    // APIM uses `protocol: 'http'` to mean "HTTP-style REST backend" (vs SOAP).
    // The actual transport is HTTPS - the URL above is `https://...` and the
    // `tls` block below validates the certificate chain on every call.
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
    circuitBreaker: {
      rules: [
        {
          name: 'primaryCircuit'
          failureCondition: {
            count: 5
            errorReasons: [
              'Server errors'
            ]
            interval: 'PT1M'
            statusCodeRanges: [
              {
                min: 500
                max: 599
              }
            ]
          }
          tripDuration: 'PT30S'
          acceptRetryAfter: true
        }
      ]
    }
  }
}

resource backendSecondary 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'openai-backend-secondary'
  properties: {
    description: 'Secondary Foundry / Azure OpenAI backend (used by the pool when primary trips).'
    type: 'Single'
    url: backendUrl
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
    circuitBreaker: {
      rules: [
        {
          name: 'secondaryCircuit'
          failureCondition: {
            count: 5
            errorReasons: [
              'Server errors'
            ]
            interval: 'PT1M'
            statusCodeRanges: [
              {
                min: 500
                max: 599
              }
            ]
          }
          tripDuration: 'PT30S'
          acceptRetryAfter: true
        }
      ]
    }
  }
}

// Backend pool referenced by every API. Priority 1 = primary, priority 2 =
// secondary. APIM routes to the lowest-priority healthy member; if all
// priority-1 members are circuit-broken it automatically promotes to
// priority-2.
resource backendPool 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'openai-backend-pool'
  properties: {
    description: 'AI Gateway model backend pool (primary + secondary, priority routing).'
    type: 'Pool'
    pool: {
      services: [
        {
          id: backendPrimary.id
          priority: 1
          weight: 1
        }
        {
          id: backendSecondary.id
          priority: 2
          weight: 1
        }
      ]
    }
  }
}

output backendPoolId string = backendPool.id
output backendPoolName string = backendPool.name
output primaryBackendName string = backendPrimary.name
output secondaryBackendName string = backendSecondary.name

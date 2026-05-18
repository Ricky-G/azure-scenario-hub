// ============================================================================
// Module: apim-openai-api.bicep
// Creates ONE Azure OpenAI API on the APIM service. Designed to be invoked
// multiple times so the gateway can expose the same backend pool under
// different customer-facing routes (e.g. "Australia East" and "Global").
//
// Each instance:
//   - Owns its own APIM API resource (path / displayName / description).
//   - Has the same operations (chat-completions, completions, embeddings).
//   - Re-uses the shared policy fragments and backend pool.
//   - Tags itself with `region` so customers can filter in the dev portal.
// ============================================================================

@description('Existing APIM service name.')
param apimServiceName string

@description('APIM API resource name (must be unique per API).')
param apiName string

@description('APIM API path - the URL prefix the customer sees, e.g. `aue` or `global`.')
param apiPath string

@description('Display name shown in the developer portal.')
param apiDisplayName string

@description('Description shown in the developer portal.')
param apiDescription string

@description('Route label baked into trace metadata + custom metric dimensions, e.g. `aue` or `global`.')
param apiRouteLabel string

@description('Region label baked into trace metadata + custom metric dimensions, e.g. `australiaeast` or `global`.')
param apiRegionLabel string

@description('Public Foundry / Azure OpenAI endpoint (no trailing /openai).')
param openAiEndpoint string

@description('Default Azure OpenAI REST API version exposed to clients.')
param openAiApiVersion string = '2024-10-21'

@description('Resource id of the Application Insights logger created on APIM.')
param appInsightsLoggerId string

@description('Optional list of APIM tag names to attach to this API.')
param tagNames array = []

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

// Strip a single trailing slash so we can safely append `/openai`.
var sanitizedEndpoint = endsWith(openAiEndpoint, '/')
  ? substring(openAiEndpoint, 0, max(length(openAiEndpoint) - 1, 0))
  : openAiEndpoint

resource openAiApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: apiName
  properties: {
    displayName: apiDisplayName
    description: apiDescription
    subscriptionRequired: true
    serviceUrl: sanitizedEndpoint
    path: apiPath
    protocols: [
      'https'
    ]
    apiType: 'http'
    type: 'http'
    subscriptionKeyParameterNames: {
      // We keep both the header and the query parameter name registered (so
      // the developer portal documents both), but the API policy at runtime
      // rejects any request that arrives with a query-string subscription
      // key. Query-string keys are easier to leak via browser referrers and
      // server access logs, so the gateway enforces header-only at the
      // policy layer.
      header: 'api-key'
      query: 'subscription-key'
    }
  }
}

// Create / reuse APIM Tags then attach them to the API. Tags surface in the
// developer portal so callers can filter "AU East only" vs "Global" APIs.
resource apiTags 'Microsoft.ApiManagement/service/tags@2024-05-01' = [for tagName in tagNames: {
  parent: apim
  name: tagName
  properties: {
    displayName: tagName
  }
}]

resource apiTagLinks 'Microsoft.ApiManagement/service/apis/tags@2024-05-01' = [for (tagName, i) in tagNames: {
  parent: openAiApi
  name: tagName
  dependsOn: [
    apiTags
  ]
}]

resource chatCompletions 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: openAiApi
  name: 'chat-completions'
  properties: {
    displayName: 'Chat Completions'
    method: 'POST'
    urlTemplate: '/openai/deployments/{deployment-id}/chat/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        type: 'string'
        required: true
      }
    ]
    request: {
      queryParameters: [
        {
          name: 'api-version'
          type: 'string'
          required: true
          defaultValue: openAiApiVersion
        }
      ]
    }
  }
}

resource completions 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: openAiApi
  name: 'completions'
  properties: {
    displayName: 'Completions'
    method: 'POST'
    urlTemplate: '/openai/deployments/{deployment-id}/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        type: 'string'
        required: true
      }
    ]
    request: {
      queryParameters: [
        {
          name: 'api-version'
          type: 'string'
          required: true
          defaultValue: openAiApiVersion
        }
      ]
    }
  }
}

resource embeddings 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: openAiApi
  name: 'embeddings'
  properties: {
    displayName: 'Embeddings'
    method: 'POST'
    urlTemplate: '/openai/deployments/{deployment-id}/embeddings'
    templateParameters: [
      {
        name: 'deployment-id'
        type: 'string'
        required: true
      }
    ]
    request: {
      queryParameters: [
        {
          name: 'api-version'
          type: 'string'
          required: true
          defaultValue: openAiApiVersion
        }
      ]
    }
  }
}

// Load the shared policy template once and substitute the per-API route /
// region labels. The template uses `__API_ROUTE__` and `__API_REGION__` as
// placeholders that this module replaces before pushing to APIM.
var apiPolicyTemplate = loadTextContent('../../policies/openai-api-policy.xml')

resource openAiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: openAiApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: replace(replace(apiPolicyTemplate, '__API_ROUTE__', apiRouteLabel), '__API_REGION__', apiRegionLabel)
  }
}

resource apiDiagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = {
  parent: openAiApi
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    // Client IP capture is OFF by default - reduces PII in logs. Flip to
    // `true` if you need client-IP based diagnostics and have a privacy
    // notice in place for callers.
    logClientIp: false
    loggerId: appInsightsLoggerId
    verbosity: 'verbose'
    metrics: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        headers: [
          'Content-Type'
          'User-Agent'
          'x-session-id'
          'x-user-id'
        ]
        body: {
          bytes: 0
        }
      }
      response: {
        headers: [
          'Content-Type'
          'x-ai-gateway-route'
          'x-ai-gateway-region'
          'x-ai-gateway-cache'
          'x-ai-gateway-fallback'
        ]
        body: {
          bytes: 0
        }
      }
    }
    backend: {
      request: {
        headers: [
          'Content-Type'
        ]
        body: {
          bytes: 0
        }
      }
      response: {
        headers: [
          'Content-Type'
        ]
        body: {
          bytes: 0
        }
      }
    }
  }
}

output apiId string = openAiApi.id
output apiName string = openAiApi.name
output apiPath string = openAiApi.properties.path

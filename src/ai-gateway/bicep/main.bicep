// ============================================================================
// AI Gateway scenario - main entry point
// ----------------------------------------------------------------------------
// Deploys an Azure API Management front-end that fronts an existing Azure AI
// Foundry / Azure OpenAI account and demonstrates the most useful AI Hub
// Gateway patterns:
//
//   * TWO customer-facing AOAI APIs on one APIM instance:
//       - "Azure OpenAI - Australia East" (path /aue/openai/...)
//       - "Azure OpenAI - Global"         (path /global/openai/...)
//     Both APIs are tagged for the developer portal so callers see which
//     route to use for their data-residency requirement. Behind the scenes
//     both share the same backend pool.
//   * Backend POOL with primary + secondary backends, priority routing, and
//     per-member circuit breaker for automatic failover.
//   * Subscription-key auth for multiple business apps / use-cases (one APIM
//     Product per app + one demo subscription per product).
//   * Managed-identity backend auth to Foundry (no AOAI keys leave Azure).
//   * Token tracking and per-app charge-back via
//     `azure-openai-emit-token-metric` -> Application Insights `customMetrics`
//     with `App ID`, `Use Case`, `Product Name`, `Deployment`, `Route`,
//     `Region Label` dimensions.
//   * Structured `<trace>` token-usage events for KQL.
//   * Per-product `azure-openai-token-limit` (TPM) demonstrating different
//     SKUs throttling independently.
//   * Service-level CORS so browser demos work.
//   * Body-hash response cache (frag-cache-lookup / frag-cache-store) for
//     repeat requests.
//   * Mock fallback policy (frag-mock-fallback) for graceful 5xx degradation.
//   * Lightweight request validation at the edge.
//   * APIM gateway logs piped into Log Analytics.
// ============================================================================

targetScope = 'subscription'

// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------
@description('Azure region for AI Gateway resources.')
param location string = 'swedencentral'

@description('Name of the resource group to create for the AI Gateway resources.')
param resourceGroupName string = 'rg-ai-gateway-demo'

@description('Short prefix used to derive globally-unique resource names.')
@minLength(3)
@maxLength(8)
param namePrefix string = 'aigw'

@description('Email shown on the APIM developer portal.')
param publisherEmail string = 'admin@contoso.com'

@description('Publisher organisation name shown on the APIM developer portal.')
param publisherName string = 'Contoso'

@description('APIM SKU. Developer is recommended for demos.')
@allowed([
  'Developer'
  'Basic'
  'Standard'
  'Premium'
])
param apimSku string = 'Developer'

@description('Resource group that contains the existing Foundry account.')
param foundryResourceGroupName string

@description('Name of the existing Foundry / Azure OpenAI account.')
param foundryAccountName string

@description('Public endpoint of the Foundry / Azure OpenAI account.')
param openAiEndpoint string

@description('Default Azure OpenAI REST API version exposed to clients.')
param openAiApiVersion string = '2024-10-21'

@description('Demo apps / use-cases to onboard. Each becomes an APIM Product with its own subscription and TPM ceiling.')
param products array = [
  {
    id: 'retail-smart-shopping'
    displayName: 'Retail Smart Shopping App'
    description: 'Frontline shopping assistant powered by GPT-4.1-mini.'
    appId: 'retail-app-001'
    useCase: 'retail-shopping'
    tpmLimit: 20000
  }
  {
    id: 'customer-care-chat'
    displayName: 'Customer Care Chat'
    description: 'Customer service chat bot powered by GPT-4.1-mini.'
    appId: 'care-chat-001'
    useCase: 'customer-care'
    tpmLimit: 10000
  }
  {
    id: 'finance-smart-analysis'
    displayName: 'Finance Smart Analysis'
    description: 'Internal finance analytics agent powered by GPT-4.1.'
    appId: 'finance-agent-001'
    useCase: 'finance-analysis'
    tpmLimit: 5000
  }
]

@description('Tags applied to all resources.')
param tags object = {
  Environment: 'Development'
  Project: 'AzureScenarioHub'
  Scenario: 'ai-gateway'
  ManagedBy: 'Bicep'
}

// ----------------------------------------------------------------------------
// Variables
// ----------------------------------------------------------------------------
var uniq = uniqueString(subscription().subscriptionId, resourceGroupName)
var apimServiceName = '${namePrefix}-apim-${uniq}'
var workspaceName = '${namePrefix}-law-${uniq}'
var appInsightsName = '${namePrefix}-appi-${uniq}'

var apiAueName = 'azure-openai-aue'
var apiGlobalName = 'azure-openai-global'

// ----------------------------------------------------------------------------
// Resources
// ----------------------------------------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module observability 'modules/log-analytics.bicep' = {
  scope: rg
  name: 'observability'
  params: {
    location: location
    workspaceName: workspaceName
    appInsightsName: appInsightsName
    tags: tags
  }
}

module apim 'modules/apim.bicep' = {
  scope: rg
  name: 'apim'
  params: {
    location: location
    apimServiceName: apimServiceName
    publisherEmail: publisherEmail
    publisherName: publisherName
    sku: apimSku
    appInsightsId: observability.outputs.appInsightsId
    appInsightsInstrumentationKey: observability.outputs.appInsightsInstrumentationKey
    logAnalyticsWorkspaceId: observability.outputs.workspaceId
    tags: tags
  }
}

module rbac 'modules/rbac.bicep' = {
  scope: resourceGroup(foundryResourceGroupName)
  name: 'foundry-rbac'
  params: {
    foundryAccountName: foundryAccountName
    apimPrincipalId: apim.outputs.apimPrincipalId
  }
}

module servicePolicy 'modules/apim-service-policy.bicep' = {
  scope: rg
  name: 'apim-service-policy'
  params: {
    apimServiceName: apim.outputs.apimName
  }
}

// Shared policy fragments - created once on the service.
module fragments 'modules/apim-fragments.bicep' = {
  scope: rg
  name: 'apim-fragments'
  params: {
    apimServiceName: apim.outputs.apimName
  }
}

// Backend pool (primary + secondary, both pointing at the Foundry endpoint
// for this single-Foundry demo). In production secondary would be a paired
// region.
module backends 'modules/apim-backends.bicep' = {
  scope: rg
  name: 'apim-backends'
  params: {
    apimServiceName: apim.outputs.apimName
    openAiEndpoint: openAiEndpoint
  }
  dependsOn: [
    rbac
  ]
}

// API #1 - Australia East
module openAiApiAue 'modules/apim-openai-api.bicep' = {
  scope: rg
  name: 'openai-api-aue'
  params: {
    apimServiceName: apim.outputs.apimName
    apiName: apiAueName
    apiPath: 'aue'
    apiDisplayName: 'Azure OpenAI - Australia East'
    apiDescription: 'Azure OpenAI route intended for AU data-residency workloads. Backed by the AI Gateway pool with Australia East priority.'
    apiRouteLabel: 'aue'
    apiRegionLabel: 'australiaeast'
    openAiEndpoint: openAiEndpoint
    openAiApiVersion: openAiApiVersion
    appInsightsLoggerId: apim.outputs.appInsightsLoggerId
    tagNames: [
      'region-australia-east'
      'data-residency-au'
    ]
  }
  dependsOn: [
    fragments
    backends
  ]
}

// API #2 - Global
module openAiApiGlobal 'modules/apim-openai-api.bicep' = {
  scope: rg
  name: 'openai-api-global'
  params: {
    apimServiceName: apim.outputs.apimName
    apiName: apiGlobalName
    apiPath: 'global'
    apiDisplayName: 'Azure OpenAI - Global'
    apiDescription: 'Azure OpenAI route intended for non-residency workloads. Routes via the AI Gateway pool with global priority.'
    apiRouteLabel: 'global'
    apiRegionLabel: 'global'
    openAiEndpoint: openAiEndpoint
    openAiApiVersion: openAiApiVersion
    appInsightsLoggerId: apim.outputs.appInsightsLoggerId
    tagNames: [
      'region-global'
    ]
  }
  dependsOn: [
    fragments
    backends
    openAiApiAue
  ]
}

module apimProducts 'modules/apim-products.bicep' = {
  scope: rg
  name: 'apim-products'
  params: {
    apimServiceName: apim.outputs.apimName
    apiNames: [
      apiAueName
      apiGlobalName
    ]
    products: products
  }
  dependsOn: [
    openAiApiAue
    openAiApiGlobal
  ]
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------
output resourceGroupName string = rg.name
output apimName string = apim.outputs.apimName
output apimGatewayUrl string = apim.outputs.apimGatewayUrl
output appInsightsName string = observability.outputs.appInsightsName
output workspaceName string = observability.outputs.workspaceName
output workspaceCustomerId string = observability.outputs.workspaceCustomerId
output productIds array = [for product in products: product.id]
output subscriptionResourceIds array = apimProducts.outputs.subscriptionResourceIds
output apiRoutes array = [
  {
    name: apiAueName
    path: 'aue'
    displayName: 'Azure OpenAI - Australia East'
    region: 'australiaeast'
  }
  {
    name: apiGlobalName
    path: 'global'
    displayName: 'Azure OpenAI - Global'
    region: 'global'
  }
]

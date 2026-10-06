// ============================================================================
// Module: apim.bicep
// Deploys the API Management service (Developer SKU) with a system-assigned
// managed identity, the Application Insights logger, and the diagnostic-
// settings wire-up to Application Insights and Log Analytics.
//
// The system-assigned MI is what APIM uses to authenticate to the Foundry /
// Azure OpenAI account. RBAC is granted in `rbac.bicep`.
// ============================================================================

@description('Azure region for the APIM service.')
param location string

@description('Globally unique APIM service name.')
@minLength(1)
@maxLength(50)
param apimServiceName string

@description('Publisher email shown on the developer portal and notifications.')
param publisherEmail string

@description('Publisher organisation name.')
param publisherName string

@description('APIM SKU. Developer is recommended for demos.')
@allowed([
  'Developer'
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Developer'

@description('Number of scale units.')
param skuCount int = 1

@description('Application Insights resource id (for the APIM logger).')
param appInsightsId string

@description('Application Insights instrumentation key (for the APIM logger).')
param appInsightsInstrumentationKey string

@description('Log Analytics workspace resource id for diagnostic settings.')
param logAnalyticsWorkspaceId string

@description('Tags applied to the APIM service.')
param tags object = {}

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimServiceName
  location: location
  tags: tags
  sku: {
    name: sku
    capacity: skuCount
  }
  identity: {
    // System-assigned MI is sufficient for the demo. The principal id is
    // exported below and used by `rbac.bicep` to grant access on the Foundry.
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    notificationSenderEmail: 'apimgmt-noreply@mail.windowsazure.com'
    virtualNetworkType: 'None'
    publicNetworkAccess: 'Enabled'
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'true'
    }
  }
}

// Application Insights logger - referenced by the API-level diagnostic so
// the gateway forwards request telemetry, custom traces (token usage
// fragments) and metrics emitted by `azure-openai-emit-token-metric`.
resource appInsightsLogger 'Microsoft.ApiManagement/service/loggers@2023-05-01-preview' = {
  parent: apim
  name: 'ai-gateway-appinsights'
  properties: {
    loggerType: 'applicationInsights'
    description: 'Application Insights logger used by the AI Gateway API.'
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
    isBuffered: true
    resourceId: appInsightsId
  }
}

// Send the APIM gateway logs (ApiManagementGatewayLogs table) to Log Analytics
// so we can query end-to-end request data with KQL alongside the token
// metrics in Application Insights.
//
// `logAnalyticsDestinationType: 'Dedicated'` makes the workspace use the
// resource-specific `ApiManagementGatewayLogs` table; without it logs land
// in the legacy `AzureDiagnostics` table and the runbook KQL won't match.
resource apimDiagnosticToLaw 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-law'
  scope: apim
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output apimName string = apim.name
output apimResourceId string = apim.id
output apimGatewayUrl string = apim.properties.gatewayUrl
output apimPrincipalId string = apim.identity.principalId
output appInsightsLoggerId string = appInsightsLogger.id

// ============================================================================
// Module: log-analytics.bicep
// Deploys a Log Analytics Workspace + an Application Insights component
// (workspace-based). Both are used by the AI Gateway:
//   - Application Insights receives token-usage metrics emitted by APIM via
//     `azure-openai-emit-token-metric` and structured `trace` events.
//   - Log Analytics receives APIM gateway diagnostic logs
//     (table: `ApiManagementGatewayLogs`) for end-to-end request analysis.
// ============================================================================

@description('Azure region for both resources.')
param location string

@description('Name of the Log Analytics Workspace.')
param workspaceName string

@description('Name of the Application Insights component.')
param appInsightsName string

@description('Workspace data retention in days.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Tags applied to both resources.')
param tags object = {}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output workspaceCustomerId string = workspace.properties.customerId
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output appInsightsConnectionString string = appInsights.properties.ConnectionString

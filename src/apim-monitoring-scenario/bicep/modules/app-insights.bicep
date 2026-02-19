// ========================================
// Application Insights Module
// ========================================

@description('The location for Application Insights')
param location string

@description('The name of the Application Insights instance')
param appInsightsName string

@description('Tags to apply to the resource')
param tags object = {}

@description('The type of application being monitored')
param applicationType string = 'web'

// ============
// Resources
// ============

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${appInsightsName}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: applicationType
  properties: {
    Application_Type: applicationType
    Flow_Type: 'Bluefield'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============
// Outputs
// ============

@description('The resource ID of Application Insights')
output appInsightsId string = appInsights.id

@description('The instrumentation key')
output instrumentationKey string = appInsights.properties.InstrumentationKey

@description('The connection string')
output connectionString string = appInsights.properties.ConnectionString

@description('The Application Insights name')
output appInsightsName string = appInsights.name

@description('The Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

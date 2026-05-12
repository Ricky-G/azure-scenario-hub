// =========================================
// Azure API Management Monitoring Scenario
// =========================================
// This template deploys:
// - Resource Group
// - API Management Developer SKU
// - Sample APIs with policies for monitoring

targetScope = 'subscription'

// ============
// Parameters
// ============

@description('The location for all resources')
param location string = 'eastus'

@description('The name of the resource group')
param resourceGroupName string = 'rg-apim-monitoring'

@description('The name of the API Management service (must be globally unique)')
@minLength(1)
@maxLength(50)
param apimServiceName string

@description('The email address of the API publisher (used for notifications)')
param publisherEmail string

@description('The name of the API publisher organization')
param publisherName string = 'Contoso'

@description('The pricing tier of the API Management service (Developer recommended for testing)')
@allowed([
  'Developer'
  'Basic'
  'Standard'
  'Premium'
])
param apimSku string = 'Developer'

@description('Enable Application Insights integration for enhanced monitoring')
param enableApplicationInsights bool = false

@description('Name prefix for Application Insights (used if enableApplicationInsights is true)')
param appInsightsNamePrefix string = 'appi'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Development'
  Project: 'AzureScenarioHub'
  Scenario: 'APIM-Monitoring'
  Purpose: 'Demo'
}

// ============
// Variables
// ============

var appInsightsName = '${appInsightsNamePrefix}-${apimServiceName}'

// ============
// Resources
// ============

// Create Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// Deploy Application Insights (optional)
module appInsights 'modules/app-insights.bicep' = if (enableApplicationInsights) {
  name: 'deploy-appinsights'
  scope: rg
  params: {
    location: location
    appInsightsName: appInsightsName
    tags: tags
  }
}

// Deploy API Management
module apim 'modules/apim.bicep' = {
  name: 'deploy-apim'
  scope: rg
  params: {
    location: location
    apimServiceName: apimServiceName
    publisherEmail: publisherEmail
    publisherName: publisherName
    sku: apimSku
    tags: tags
    enableApplicationInsights: enableApplicationInsights
    appInsightsInstrumentationKey: enableApplicationInsights ? appInsights!.outputs.instrumentationKey : ''
    appInsightsId: enableApplicationInsights ? appInsights!.outputs.appInsightsId : ''
    logAnalyticsWorkspaceId: enableApplicationInsights ? appInsights!.outputs.logAnalyticsWorkspaceId : ''
  }
}

// Deploy Sample APIs
module apis 'modules/apim-apis.bicep' = {
  name: 'deploy-apim-apis'
  scope: rg
  params: {
    apimServiceName: apimServiceName
  }
  dependsOn: [
    apim
  ]
}

// Deploy APIM Monitoring Workbook
module workbook 'modules/apim-workbook.bicep' = {
  name: 'deploy-apim-workbook'
  scope: rg
  params: {
    location: location
    apimServiceName: apimServiceName
    apimResourceId: apim.outputs.apimId
    workbookName: 'APIM-Monitoring-Dashboard'
    tags: tags
  }
}

// ============
// Outputs
// ============

@description('The name of the resource group')
output resourceGroupName string = rg.name

@description('The name of the API Management service')
output apimServiceName string = apimServiceName

@description('The gateway URL of the API Management service')
output apimGatewayUrl string = apim.outputs.gatewayUrl

@description('The portal URL of the API Management service')
output apimPortalUrl string = apim.outputs.portalUrl

@description('The developer portal URL')
output apimDeveloperPortalUrl string = apim.outputs.developerPortalUrl

@description('Application Insights Name (if enabled)')
output appInsightsName string = enableApplicationInsights ? appInsightsName : ''

@description('Application Insights Instrumentation Key (if enabled)')
output appInsightsInstrumentationKey string = enableApplicationInsights ? appInsights!.outputs.instrumentationKey : ''

@description('Log Analytics Workspace ID (if Application Insights enabled)')
output logAnalyticsWorkspaceId string = enableApplicationInsights ? appInsights!.outputs.logAnalyticsWorkspaceId : ''

@description('List of deployed sample APIs')
output sampleApis array = [
  {
    name: 'Weather API'
    path: '/weather/{city}'
    description: 'Demonstrates caching policies'
  }
  {
    name: 'Product Search API'
    path: '/products/search'
    description: 'Demonstrates rate limiting and quotas'
  }
  {
    name: 'User Validation API'
    path: '/users/validate'
    description: 'Demonstrates validation and transformation'
  }
  {
    name: 'Currency Conversion API'
    path: '/currency/convert'
    description: 'Demonstrates policy expressions'
  }
  {
    name: 'Health Monitor API'
    path: '/health/status'
    description: 'Health check endpoint'
  }
  {
    name: 'Delay Simulator API'
    path: '/simulate/delay'
    description: 'Performance testing endpoint'
  }
]

@description('The resource ID of the monitoring workbook')
output workbookId string = workbook.outputs.workbookId

@description('The name of the monitoring workbook')
output workbookName string = workbook.outputs.workbookName

@description('The display name of the monitoring workbook')
output workbookDisplayName string = workbook.outputs.workbookDisplayName

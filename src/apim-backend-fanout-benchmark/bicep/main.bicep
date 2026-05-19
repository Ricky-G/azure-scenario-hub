// ========================================
// APIM Backend Fan-out Benchmark — entry point
// ========================================
// Deploys:
//   - Resource Group (subscription scope)
//   - Shared Log Analytics + App Insights
//   - One mock backend Function App (Premium EP1, always-ready)
//   - APIM-A (shared backend + rewrite-uri pattern)
//   - APIM-B (one backend per API pattern)
// Both APIMs are configured identically apart from the variable under test.

targetScope = 'subscription'

@description('Azure region for all resources')
param location string = 'australiaeast'

@description('3–8 char prefix used to derive every resource name')
@minLength(3)
@maxLength(8)
param namePrefix string = 'apimfo'

@description('Resource group to create')
param resourceGroupName string = 'rg-${namePrefix}-benchmark'

@description('Publisher email used by both APIMs')
param publisherEmail string = 'admin@example.com'

@description('Publisher name used by both APIMs')
param publisherName string = 'Benchmark'

@description('Number of APIs per APIM (kept identical between A and B)')
@minValue(1)
@maxValue(50)
param apiCount int = 10

@description('Tags applied to every resource')
param tags object = {
  Environment: 'Development'
  Project: 'AzureScenarioHub'
  Scenario: 'APIM-Backend-Fanout-Benchmark'
  ManagedBy: 'Bicep'
}

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = {
  scope: rg
  name: 'deploy-monitoring'
  params: {
    location: location
    namePrefix: namePrefix
    tags: tags
  }
}

module backend 'modules/backend-functionapp.bicep' = {
  scope: rg
  name: 'deploy-backend'
  params: {
    location: location
    namePrefix: namePrefix
    tags: tags
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
  }
}

// APIM-A and APIM-B deploy in parallel — total wall-clock time ≈ 45 minutes,
// not 90.
module apimA 'modules/apim.bicep' = {
  scope: rg
  name: 'deploy-apim-a'
  params: {
    location: location
    apimServiceName: 'apim-${namePrefix}-a-${uniqueString(rg.id)}'
    publisherEmail: publisherEmail
    publisherName: publisherName
    sku: 'Premium'
    capacity: 1
    appInsightsId: monitoring.outputs.appInsightsId
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    tags: tags
  }
}

module apimB 'modules/apim.bicep' = {
  scope: rg
  name: 'deploy-apim-b'
  params: {
    location: location
    apimServiceName: 'apim-${namePrefix}-b-${uniqueString(rg.id)}'
    publisherEmail: publisherEmail
    publisherName: publisherName
    sku: 'Premium'
    capacity: 1
    appInsightsId: monitoring.outputs.appInsightsId
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    tags: tags
  }
}

module apimAConfig 'modules/apim-a-shared-backend.bicep' = {
  scope: rg
  name: 'configure-apim-a'
  params: {
    apimServiceName: apimA.outputs.apimName
    backendHostname: backend.outputs.functionAppDefaultHostname
    apiCount: apiCount
  }
}

module apimBConfig 'modules/apim-b-per-api-backend.bicep' = {
  scope: rg
  name: 'configure-apim-b'
  params: {
    apimServiceName: apimB.outputs.apimName
    backendHostname: backend.outputs.functionAppDefaultHostname
    apiCount: apiCount
  }
}

output resourceGroupName string = rg.name
output functionAppName string = backend.outputs.functionAppName
output functionAppHostname string = backend.outputs.functionAppDefaultHostname
output apimAName string = apimA.outputs.apimName
output apimAGatewayUrl string = apimA.outputs.gatewayUrl
output apimBName string = apimB.outputs.apimName
output apimBGatewayUrl string = apimB.outputs.gatewayUrl
output appInsightsName string = monitoring.outputs.appInsightsName
output logAnalyticsWorkspaceName string = monitoring.outputs.workspaceName
output apiCount int = apiCount

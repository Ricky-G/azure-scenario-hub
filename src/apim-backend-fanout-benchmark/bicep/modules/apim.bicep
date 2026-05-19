// ========================================
// Reusable APIM Premium module
// ========================================
// Deploys an APIM Premium instance, hooks it to the shared App Insights logger,
// and configures 100% sampling diagnostics with headers logged and bodies disabled.
// Used by BOTH APIM-A and APIM-B with identical configuration so that policy /
// backend modelling is the only variable.

@description('Azure region')
param location string

@description('Globally-unique APIM service name')
@minLength(1)
@maxLength(50)
param apimServiceName string

@description('Publisher email')
param publisherEmail string

@description('Publisher name')
param publisherName string

@description('APIM SKU (must be Premium for the benchmark)')
@allowed([
  'Premium'
])
param sku string = 'Premium'

@description('APIM capacity (units)')
param capacity int = 1

@description('Application Insights resource ID')
param appInsightsId string

@description('Application Insights instrumentation key')
param appInsightsInstrumentationKey string

@description('Log Analytics workspace resource ID for diagnostic settings')
param logAnalyticsWorkspaceId string

@description('Tags applied to all resources')
param tags object = {}

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimServiceName
  location: location
  tags: tags
  sku: {
    name: sku
    capacity: capacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'None'
    publicNetworkAccess: 'Enabled'
    apiVersionConstraint: {}
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'true'
    }
  }
}

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2023-05-01-preview' = {
  parent: apim
  name: 'applicationinsights-logger'
  properties: {
    loggerType: 'applicationInsights'
    description: 'Shared App Insights logger'
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
    isBuffered: true
    resourceId: appInsightsId
  }
}

resource apimDiagnostics 'Microsoft.ApiManagement/service/diagnostics@2023-05-01-preview' = {
  parent: apim
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    logClientIp: true
    httpCorrelationProtocol: 'W3C'
    verbosity: 'information'
    loggerId: apimLogger.id
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        headers: [
          'Content-Type'
          'User-Agent'
          'X-Correlation-Id'
          'traceparent'
        ]
        // Bodies intentionally disabled to avoid distorting latency.
      }
      response: {
        headers: [
          'Content-Type'
          'X-Correlation-Id'
          'traceparent'
        ]
      }
    }
    backend: {
      request: {
        headers: [
          'Content-Type'
        ]
      }
      response: {
        headers: [
          'Content-Type'
        ]
      }
    }
  }
}

resource apimDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'apim-diagnostics-law'
  scope: apim
  properties: {
    workspaceId: logAnalyticsWorkspaceId
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

output apimId string = apim.id
output apimName string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output principalId string = apim.identity.principalId

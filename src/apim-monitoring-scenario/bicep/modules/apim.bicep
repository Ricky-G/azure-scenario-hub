// ========================================
// API Management Module
// ========================================

@description('The location for the API Management service')
param location string

@description('The name of the API Management service')
param apimServiceName string

@description('The email address of the publisher')
param publisherEmail string

@description('The name of the publisher organization')
param publisherName string

@description('The pricing tier of the API Management service')
@allowed([
  'Developer'
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Developer'

@description('The capacity (number of deployed units) of the API Management service')
param skuCount int = 1

@description('Tags to apply to the resource')
param tags object = {}

@description('Enable Application Insights integration')
param enableApplicationInsights bool = false

@description('Application Insights Instrumentation Key')
param appInsightsInstrumentationKey string = ''

@description('Application Insights Resource ID')
param appInsightsId string = ''

@description('Log Analytics Workspace Resource ID for diagnostic settings')
param logAnalyticsWorkspaceId string = ''

// ============
// Resources
// ============

// API Management Service
resource apimService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimServiceName
  location: location
  tags: tags
  sku: {
    name: sku
    capacity: skuCount
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    notificationSenderEmail: 'apimgmt-noreply@mail.windowsazure.com'
    virtualNetworkType: 'None'
    disableGateway: false
    apiVersionConstraint: {}
    publicNetworkAccess: 'Enabled'
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'true'
    }
  }
}

// Application Insights Logger (if enabled)
resource apimLogger 'Microsoft.ApiManagement/service/loggers@2023-05-01-preview' = if (enableApplicationInsights) {
  parent: apimService
  name: 'applicationinsights-logger'
  properties: {
    loggerType: 'applicationInsights'
    description: 'Application Insights logger for API Management'
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
    isBuffered: true
    resourceId: appInsightsId
  }
}

// Diagnostic Settings for all APIs (if Application Insights enabled)
// This configuration captures full request/response data for incident tracking
resource apimDiagnostics 'Microsoft.ApiManagement/service/diagnostics@2023-05-01-preview' = if (enableApplicationInsights) {
  parent: apimService
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    logClientIp: true
    httpCorrelationProtocol: 'W3C'
    verbosity: 'information'
    loggerId: enableApplicationInsights ? apimLogger.id : ''
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        headers: [
          'Content-Type'
          'User-Agent'
          'Authorization'
          'X-Forwarded-For'
          'X-Correlation-Id'
          'traceparent'
          'tracestate'
        ]
        body: {
          bytes: 8192  // Log first 8KB of request body
        }
        dataMasking: {
          queryParams: [
            {
              value: '*'
              mode: 'Hide'
            }
          ]
          headers: [
            {
              value: 'Authorization'
              mode: 'Hide'
            }
          ]
        }
      }
      response: {
        headers: [
          'Content-Type'
          'X-Correlation-Id'
          'traceparent'
          'tracestate'
        ]
        body: {
          bytes: 8192  // Log first 8KB of response body
        }
      }
    }
    backend: {
      request: {
        headers: [
          'Content-Type'
          'Accept'
        ]
        body: {
          bytes: 8192
        }
      }
      response: {
        headers: [
          'Content-Type'
        ]
        body: {
          bytes: 8192
        }
      }
    }
  }
}

// Create a default Product with unlimited quota
resource unlimitedProduct 'Microsoft.ApiManagement/service/products@2023-05-01-preview' = {
  parent: apimService
  name: 'unlimited'
  properties: {
    displayName: 'Unlimited'
    description: 'Unlimited access to all APIs for testing'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

// Create a Starter Product with rate limiting
resource starterProduct 'Microsoft.ApiManagement/service/products@2023-05-01-preview' = {
  parent: apimService
  name: 'starter'
  properties: {
    displayName: 'Starter'
    description: 'Rate-limited access for starter plan'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

// Azure Monitor Diagnostic Settings - Send APIM logs to Log Analytics Workspace
resource apimDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableApplicationInsights && !empty(logAnalyticsWorkspaceId)) {
  name: 'apim-diagnostics-law'
  scope: apimService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// ============
// Outputs
// ============

@description('The resource ID of the API Management service')
output apimId string = apimService.id

@description('The name of the API Management service')
output apimName string = apimService.name

@description('The gateway URL of the API Management service')
output gatewayUrl string = apimService.properties.gatewayUrl

@description('The portal URL of the API Management service')
output portalUrl string = apimService.properties.portalUrl

@description('The developer portal URL')
output developerPortalUrl string = apimService.properties.developerPortalUrl

@description('The principal ID of the system-assigned managed identity')
output principalId string = apimService.identity.principalId

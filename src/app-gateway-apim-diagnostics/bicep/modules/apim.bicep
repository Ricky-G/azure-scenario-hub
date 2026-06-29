// ========================================
// API Management Module
// ========================================
// Deploys API Management (Developer tier by default), a self-contained
// "Hello World" API that returns a mock response (no backend required),
// and a comprehensive Azure Monitor diagnostic setting that streams every
// available log category and all metrics to Log Analytics.

@description('Location for the API Management service.')
param location string

@description('Name of the API Management service (must be globally unique).')
@minLength(1)
@maxLength(50)
param apimServiceName string

@description('Publisher email address (receives service notifications).')
param publisherEmail string

@description('Publisher organisation name.')
param publisherName string

@description('API Management pricing tier.')
@allowed([
  'Developer'
  'Basic'
  'Standard'
  'Premium'
])
param skuName string = 'Developer'

@description('Number of scale units.')
@minValue(1)
param skuCapacity int = 1

@description('Log Analytics Workspace resource ID for diagnostic settings.')
param logAnalyticsWorkspaceId string

@description('Tags to apply to the resources.')
param tags object = {}

// ----------------------------------------
// Variables
// ----------------------------------------

var helloApiName = 'hello-world-api'

// Operation-level policy that returns a mock "Hello, World!" response.
// Because the response is generated entirely by the policy, no backend
// service is required - the API is fully self-contained.
var helloOperationPolicyXml = '''
<policies>
  <inbound>
    <base />
    <return-response>
      <set-status code="200" reason="OK" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>@{
        return new JObject(
          new JProperty("message", "Hello, World!"),
          new JProperty("description", "Served by Azure API Management, fronted by Azure Application Gateway."),
          new JProperty("requestedHost", context.Request.OriginalUrl.Host),
          new JProperty("forwardedFor", context.Request.Headers.GetValueOrDefault("X-Forwarded-For", "n/a")),
          new JProperty("timestamp", DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"))
        ).ToString();
      }</set-body>
    </return-response>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''

// ----------------------------------------
// Resources
// ----------------------------------------

resource apimService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimServiceName
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    notificationSenderEmail: 'apimgmt-noreply@mail.windowsazure.com'
    // Public APIM - the Application Gateway routes to its public gateway endpoint.
    virtualNetworkType: 'None'
    publicNetworkAccess: 'Enabled'
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
    }
  }
}

// Hello World API. subscriptionRequired = false so it can be called without a
// subscription key, which keeps the end-to-end demo frictionless.
resource helloApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apimService
  name: helloApiName
  properties: {
    displayName: 'Hello World API'
    description: 'A self-contained Hello World API used to demonstrate routing from Application Gateway to APIM.'
    path: 'hello'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    apiType: 'http'
  }
}

// GET operation. The URL template "/" combined with the API path "hello"
// produces the public route /hello.
resource helloOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: helloApi
  name: 'get-hello'
  properties: {
    displayName: 'Get Hello'
    method: 'GET'
    urlTemplate: '/'
    responses: [
      {
        statusCode: 200
        description: 'Successful Hello World response.'
      }
    ]
  }
}

resource helloOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-05-01-preview' = {
  parent: helloOperation
  name: 'policy'
  properties: {
    format: 'xml'
    value: helloOperationPolicyXml
  }
}

// =========================================================================
// Azure Monitor Diagnostic Settings for API Management
// -------------------------------------------------------------------------
// Streams EVERY available APIM log category plus all metrics to Log Analytics.
// Available APIM log categories:
//   - GatewayLogs              : every request that hits the APIM gateway
//   - WebSocketConnectionLogs  : WebSocket connection lifecycle events
// (DeveloperPortalAuditLogs is also available on supported tiers; add it as an
//  extra category entry if you want developer-portal audit events as well.)
// AllMetrics captures Capacity, Requests, Duration, and other APIM metrics.
// =========================================================================
resource apimDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'apim-all-diagnostics'
  scope: apimService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
      }
      {
        category: 'WebSocketConnectionLogs'
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

// ----------------------------------------
// Outputs
// ----------------------------------------

@description('Resource ID of the API Management service.')
output apimId string = apimService.id

@description('Name of the API Management service.')
output apimName string = apimService.name

@description('Gateway URL of the API Management service.')
output gatewayUrl string = apimService.properties.gatewayUrl

@description('Gateway host name of the API Management service.')
output apimHostName string = replace(apimService.properties.gatewayUrl, 'https://', '')

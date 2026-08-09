@description('Azure region for API Management.')
param location string

@description('Globally unique API Management service name.')
@minLength(1)
@maxLength(50)
param apimServiceName string

@description('Publisher email for API Management notifications.')
param publisherEmail string

@description('Publisher organization name shown in API Management.')
param publisherName string

@description('Resource ID of the dedicated API Management subnet.')
param apimSubnetId string

@description('Private IP address of the AKS internal load balancer.')
param aksBackendPrivateIp string

@description('Resource ID of the Log Analytics workspace.')
param logAnalyticsWorkspaceId string

@description('API Management SKU. Premium is the scenario default; Developer is available for lower-cost template development.')
@allowed([
  'Premium'
  'Developer'
])
param apimSku string = 'Premium'

@description('Tags applied to API Management.')
param tags object

var managedApiName = 'happy-api'
var drApiName = 'dr-api'
var selfHostedGatewayName = 'mock-onprem-gateway'
var managedApiPolicy = '''
<policies>
  <inbound>
    <base />
    <cors allow-credentials="false">
      <allowed-origins><origin>*</origin></allowed-origins>
      <allowed-methods><method>GET</method></allowed-methods>
      <allowed-headers><header>*</header></allowed-headers>
      <expose-headers>
        <header>X-Scenario-Route</header>
        <header>X-Scenario-Request-Id</header>
        <header>X-APIM-Gateway</header>
        <header>X-APIM-Service</header>
        <header>X-AppGateway-Hop</header>
        <header>X-Backend-Service</header>
        <header>X-Backend-Request-Id</header>
      </expose-headers>
    </cors>
    <set-header name="X-Scenario-Request-Id" exists-action="override"><value>@(context.Request.Headers.GetValueOrDefault("X-Scenario-Request-Id", context.RequestId.ToString()))</value></set-header>
  </inbound>
  <backend><base /></backend>
  <outbound>
    <base />
    <set-header name="X-Scenario-Route" exists-action="override"><value>happy-managed</value></set-header>
    <set-header name="X-APIM-Gateway" exists-action="override"><value>managed</value></set-header>
    <set-header name="X-APIM-Service" exists-action="override"><value>@(context.Deployment.ServiceName)</value></set-header>
    <set-header name="X-Scenario-Request-Id" exists-action="override"><value>@(context.Request.Headers.GetValueOrDefault("X-Scenario-Request-Id", context.RequestId.ToString()))</value></set-header>
  </outbound>
  <on-error><base /></on-error>
</policies>
'''
var drApiPolicy = '''
<policies>
  <inbound>
    <base />
    <cors allow-credentials="false">
      <allowed-origins><origin>*</origin></allowed-origins>
      <allowed-methods><method>GET</method></allowed-methods>
      <allowed-headers><header>*</header></allowed-headers>
      <expose-headers>
        <header>X-Scenario-Route</header>
        <header>X-Scenario-Request-Id</header>
        <header>X-APIM-Gateway</header>
        <header>X-APIM-Service</header>
        <header>X-Backend-Service</header>
        <header>X-Backend-Request-Id</header>
      </expose-headers>
    </cors>
    <set-header name="X-Scenario-Request-Id" exists-action="override"><value>@(context.Request.Headers.GetValueOrDefault("X-Scenario-Request-Id", context.RequestId.ToString()))</value></set-header>
  </inbound>
  <backend><base /></backend>
  <outbound>
    <base />
    <set-header name="X-Scenario-Route" exists-action="override"><value>dr-self-hosted</value></set-header>
    <set-header name="X-APIM-Gateway" exists-action="override"><value>self-hosted</value></set-header>
    <set-header name="X-APIM-Service" exists-action="override"><value>@(context.Deployment.ServiceName)</value></set-header>
    <set-header name="X-Scenario-Request-Id" exists-action="override"><value>@(context.Request.Headers.GetValueOrDefault("X-Scenario-Request-Id", context.RequestId.ToString()))</value></set-header>
  </outbound>
  <on-error><base /></on-error>
</policies>
'''

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimServiceName
  location: location
  tags: tags
  sku: {
    name: apimSku
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
    publicNetworkAccess: 'Enabled'
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
    }
  }
}

resource managedApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  name: managedApiName
  parent: apim
  properties: {
    displayName: 'Happy Path Hello World'
    description: 'Managed APIM gateway route to the AKS internal load balancer.'
    path: 'happy'
    protocols: [
      'https'
    ]
    serviceUrl: 'http://${aksBackendPrivateIp}'
    subscriptionRequired: false
    apiType: 'http'
  }
}

resource managedHelloOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  name: 'get-hello'
  parent: managedApi
  properties: {
    displayName: 'Get Hello World through managed APIM'
    method: 'GET'
    urlTemplate: '/hello'
    templateParameters: []
    responses: [
      {
        statusCode: 200
        description: 'Hello World response from AKS.'
      }
    ]
  }
}

resource managedPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  name: 'policy'
  parent: managedApi
  properties: {
    format: 'rawxml'
    value: managedApiPolicy
  }
}

resource drApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  name: drApiName
  parent: apim
  properties: {
    displayName: 'DR Path Hello World'
    description: 'Self-hosted APIM gateway route to the in-cluster AKS backend.'
    path: 'dr'
    protocols: [
      'http'
      'https'
    ]
    serviceUrl: 'http://hello-backend.default.svc.cluster.local'
    subscriptionRequired: false
    apiType: 'http'
  }
}

resource drHelloOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  name: 'get-hello'
  parent: drApi
  properties: {
    displayName: 'Get Hello World through self-hosted APIM'
    method: 'GET'
    urlTemplate: '/hello'
    templateParameters: []
    responses: [
      {
        statusCode: 200
        description: 'Hello World response from AKS.'
      }
    ]
  }
}

resource drPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  name: 'policy'
  parent: drApi
  properties: {
    format: 'rawxml'
    value: drApiPolicy
  }
}

resource selfHostedGateway 'Microsoft.ApiManagement/service/gateways@2024-05-01' = {
  name: selfHostedGatewayName
  parent: apim
  properties: {
    description: 'APIM self-hosted gateway deployed to the mock on-premises AKS cluster.'
    locationData: {
      name: 'Mock on-premises data center'
      city: 'Wellington'
      district: 'Wellington'
      countryOrRegion: 'New Zealand'
    }
  }
}

resource drApiAssociation 'Microsoft.ApiManagement/service/gateways/apis@2024-05-01' = {
  name: drApi.name
  parent: selfHostedGateway
  properties: {
    provisioningState: 'created'
  }
}

resource apimDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'apim-diagnostics'
  scope: apim
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'GatewayLogs'
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
output apimPrivateIpAddress string = apim.properties.privateIPAddresses[0]
output apimGatewayHostname string = '${apim.name}.azure-api.net'
output selfHostedGatewayName string = selfHostedGateway.name
output selfHostedGatewayId string = selfHostedGateway.id
output selfHostedGatewayConfigurationUri string = 'https://${apim.name}.configuration.azure-api.net'
output managedApiUrl string = 'https://${apim.name}.azure-api.net/happy/hello'
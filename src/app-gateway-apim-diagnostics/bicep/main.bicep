// =====================================================================
// Application Gateway + API Management with Comprehensive Diagnostics
// =====================================================================
// This scenario is built to SHOWCASE every diagnostic setting that is
// available for Azure Application Gateway and Azure API Management, with
// all logs and metrics streamed to a single Log Analytics Workspace.
//
// Deploys (resource-group scope):
//   - Log Analytics Workspace  -> central sink for ALL diagnostics
//   - Virtual Network          -> dedicated subnet for Application Gateway
//   - Public IP (Standard)     -> public entry point with a DNS label
//   - API Management (Developer tier, public) + a "Hello World" API
//   - Application Gateway (WAF_v2) routing public traffic to APIM
//   - FULL diagnostic settings on BOTH App Gateway and APIM
//
// Request flow demonstrated by the demo:
//   client -> http://<appgw-fqdn>/hello          (App Gateway, port 80)
//          -> https://<apim>.azure-api.net/hello  (APIM gateway, port 443)
//          -> mock "Hello, World!" JSON returned by an APIM policy
// =====================================================================

targetScope = 'resourceGroup'

// ============
// Parameters
// ============

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Short prefix applied to all resource names for uniqueness.')
@minLength(3)
@maxLength(8)
param namePrefix string = 'agwdiag'

@description('Publisher email for API Management. Receives service notifications (must be a valid address).')
param publisherEmail string = 'admin@example.com'

@description('Publisher organisation name shown in the API Management developer portal.')
param publisherName string = 'Azure Scenario Hub'

@description('API Management pricing tier. Developer is the cheapest tier that exposes the full diagnostic surface.')
@allowed([
  'Developer'
  'Basic'
  'Standard'
  'Premium'
])
param apimSkuName string = 'Developer'

@description('Number of scale units for API Management.')
@minValue(1)
param apimCapacity int = 1

// ============
// Variables
// ============

var scenarioName = 'AppGateway-APIM-Diagnostics'
var suffix = uniqueString(resourceGroup().id)

// Resource names are derived deterministically so users never type full names.
var logAnalyticsName = '${namePrefix}-law-${suffix}'
var apimName = toLower('${namePrefix}apim${suffix}')
var vnetName = '${namePrefix}-vnet'
var appGwName = '${namePrefix}-appgw'
var publicIpName = '${namePrefix}-appgw-pip'
var wafPolicyName = '${namePrefix}-waf-policy'
var dnsLabel = toLower('${namePrefix}-${suffix}')

// APIM default gateway host name is deterministic, so we can pass it to the
// Application Gateway backend without creating a dependency on the (slow) APIM
// deployment. This lets both resources provision in parallel.
var apimHostName = '${apimName}.azure-api.net'

// Consistent tags applied to every resource.
var commonTags = {
  Environment: 'Development'
  Project: 'AzureScenarioHub'
  Scenario: scenarioName
  ManagedBy: 'Bicep'
}

// ============
// Resources
// ============

// Central Log Analytics Workspace that receives every diagnostic log and metric.
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'deploy-log-analytics'
  params: {
    location: location
    workspaceName: logAnalyticsName
    tags: commonTags
  }
}

// Virtual network, dedicated Application Gateway subnet, and public IP.
module network 'modules/network.bicep' = {
  name: 'deploy-network'
  params: {
    location: location
    vnetName: vnetName
    publicIpName: publicIpName
    dnsLabel: dnsLabel
    tags: commonTags
  }
}

// API Management service + Hello World API + comprehensive diagnostic settings.
module apim 'modules/apim.bicep' = {
  name: 'deploy-apim'
  params: {
    location: location
    apimServiceName: apimName
    publisherEmail: publisherEmail
    publisherName: publisherName
    skuName: apimSkuName
    skuCapacity: apimCapacity
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: commonTags
  }
}

// Application Gateway (WAF_v2) fronting APIM + comprehensive diagnostic settings.
module appGateway 'modules/app-gateway.bicep' = {
  name: 'deploy-app-gateway'
  params: {
    location: location
    appGatewayName: appGwName
    wafPolicyName: wafPolicyName
    subnetId: network.outputs.appGwSubnetId
    publicIpId: network.outputs.publicIpId
    apimHostName: apimHostName
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: commonTags
  }
}

// ============
// Outputs
// ============

@description('Name of the Log Analytics Workspace receiving all diagnostics.')
output logAnalyticsWorkspaceName string = logAnalytics.outputs.workspaceName

@description('Resource ID of the Log Analytics Workspace.')
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId

@description('Name of the API Management service.')
output apimName string = apim.outputs.apimName

@description('Gateway URL of the API Management service.')
output apimGatewayUrl string = apim.outputs.gatewayUrl

@description('Public IP address of the Application Gateway.')
output appGatewayPublicIp string = network.outputs.publicIpAddress

@description('Fully qualified domain name of the Application Gateway public IP.')
output appGatewayFqdn string = network.outputs.publicIpFqdn

@description('End-to-end demo URL: call this to reach APIM through the Application Gateway.')
output helloWorldUrlViaAppGateway string = 'http://${network.outputs.publicIpFqdn}/hello'

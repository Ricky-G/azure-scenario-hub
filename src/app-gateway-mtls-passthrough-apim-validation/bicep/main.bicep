// =====================================================================
// Client-cert auth through Application Gateway PASSTHROUGH -> APIM
// =====================================================================
// Proof-of-concept that proves how secure a mTLS PASSTHROUGH design can
// be made when ALL certificate trust validation happens in API Management
// (never at the gateway) and the gateway stays in passthrough mode.
//
// Deploys (resource-group scope):
//   - Virtual network with App Gateway + APIM subnets (locked-down NSGs)
//   - Log Analytics workspace (evidence sink)
//   - Key Vault holding the trust material (Root CA + client allow list)
//   - API Management (Developer, INTERNAL VNet) = the trust anchor
//   - WAF policy (OWASP, Prevention) retained on the gateway
//   - Application Gateway (WAF_v2) in mTLS PASSTHROUGH mode
//
// Request flow:
//   client (mTLS) -> App Gateway :443 (passthrough, forwards cert header)
//                 -> APIM (internal) validates cert -> 200 / 403
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
param namePrefix string = 'mtlspoc'

@description('Publisher email for API Management notifications.')
param publisherEmail string = 'admin@example.com'

@description('Publisher organisation name shown in API Management.')
param publisherName string = 'Azure Scenario Hub'

@description('Frontend TLS host name (SNI) that clients connect to via curl --resolve.')
param frontendHostName string = 'api.mtls-poc.local'

@description('Base64-encoded PFX for the App Gateway frontend server certificate.')
@secure()
param serverCertData string

@description('Password for the App Gateway frontend server certificate PFX.')
@secure()
param serverCertPassword string

@description('Trusted Root CA certificate, DER encoded then base64 (single line).')
@secure()
param trustedRootCaDerB64 string

@description('Per-client pinned-thumbprint allow list: client1:THUMB|client2:THUMB.')
@secure()
param clientCertAllowlist string

@description('Application Gateway SKU tier. WAF_v2 is the real scenario; Standard_v2 exists only for isolation testing.')
@allowed([
  'WAF_v2'
  'Standard_v2'
])
param appGatewaySkuTier string = 'WAF_v2'

@description('Certificate validation model APIM enforces: pinned (thumbprint allow list) or chain (Root CA signature).')
@allowed([
  'pinned'
  'chain'
])
param certValidationMode string = 'pinned'

// ============
// Variables
// ============

var scenarioName = 'AppGateway-mTLS-Passthrough-APIM'
var suffix = uniqueString(resourceGroup().id)

var logAnalyticsName = '${namePrefix}-law-${suffix}'
var keyVaultName = take(toLower('${namePrefix}kv${suffix}'), 24)
var apimName = toLower('${namePrefix}apim${suffix}')
var appGwName = '${namePrefix}-appgw'
var wafPolicyName = '${namePrefix}-waf'

var commonTags = {
  Environment: 'Development'
  Project: 'AzureScenarioHub'
  Scenario: scenarioName
  ManagedBy: 'Bicep'
}

// Policy documents authored as separate, readable XML files.
var apiPolicyXml = loadTextContent('../apim/api-policy.xml')
var client1PolicyXml = loadTextContent('../apim/operation-client1-policy.xml')
var client2PolicyXml = loadTextContent('../apim/operation-client2-policy.xml')
var whoamiPolicyXml = loadTextContent('../apim/operation-whoami-policy.xml')

// ============
// Resources
// ============

module network 'modules/network.bicep' = {
  name: 'deploy-network'
  params: {
    location: location
    namePrefix: namePrefix
    suffix: suffix
    tags: commonTags
  }
}

module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'deploy-log-analytics'
  params: {
    location: location
    workspaceName: logAnalyticsName
    tags: commonTags
  }
}

module wafPolicy 'modules/waf-policy.bicep' = {
  name: 'deploy-waf-policy'
  params: {
    location: location
    wafPolicyName: wafPolicyName
    tags: commonTags
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'deploy-keyvault'
  params: {
    location: location
    keyVaultName: keyVaultName
    tags: commonTags
    trustedRootCaDerB64: trustedRootCaDerB64
    clientCertAllowlist: clientCertAllowlist
  }
}

// API Management (Internal VNet) - the long pole (~30-45 min).
module apim 'modules/apim.bicep' = {
  name: 'deploy-apim'
  params: {
    location: location
    apimServiceName: apimName
    publisherEmail: publisherEmail
    publisherName: publisherName
    apimSubnetId: network.outputs.apimSubnetId
    apimPublicIpId: network.outputs.apimPublicIpId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: commonTags
  }
}

// Grant the APIM managed identity read access to the Key Vault secrets.
module kvRbac 'modules/kv-rbac.bicep' = {
  name: 'deploy-kv-rbac'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    principalId: apim.outputs.principalId
  }
}

// API + operations + trust-material named values + validation policies.
module apimConfig 'modules/apim-config.bicep' = {
  name: 'deploy-apim-config'
  params: {
    apimName: apim.outputs.apimName
    rootSecretIdentifier: keyVault.outputs.rootSecretIdentifier
    allowlistSecretIdentifier: keyVault.outputs.allowlistSecretIdentifier
    apiPolicyXml: apiPolicyXml
    client1PolicyXml: client1PolicyXml
    client2PolicyXml: client2PolicyXml
    whoamiPolicyXml: whoamiPolicyXml
    certValidationMode: certValidationMode
  }
  dependsOn: [
    kvRbac
  ]
}

// Application Gateway (WAF_v2) in PASSTHROUGH mode - needs APIM's private IP.
module appGateway 'modules/app-gateway.bicep' = {
  name: 'deploy-app-gateway'
  params: {
    location: location
    appGatewayName: appGwName
    appGwSubnetId: network.outputs.appGwSubnetId
    appGwPublicIpId: network.outputs.appGwPublicIpId
    serverCertData: serverCertData
    serverCertPassword: serverCertPassword
    apimPrivateIp: apim.outputs.privateIpAddress
    apimGatewayHost: apim.outputs.gatewayHostName
    wafPolicyId: wafPolicy.outputs.wafPolicyId
    skuTier: appGatewaySkuTier
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: commonTags
  }
}

// ============
// Outputs
// ============

@description('Public IP address of the Application Gateway (use with curl --resolve).')
output appGatewayPublicIp string = network.outputs.appGwPublicIpAddress

@description('Azure-assigned FQDN of the Application Gateway public IP.')
output appGatewayFqdn string = network.outputs.appGwFqdn

@description('Frontend TLS host name that clients must present as SNI.')
output frontendHostName string = frontendHostName

@description('API Management service name.')
output apimName string = apim.outputs.apimName

@description('APIM private IP inside the VNet (backend target for App Gateway).')
output apimPrivateIp string = apim.outputs.privateIpAddress

@description('Key Vault holding the trust material.')
output keyVaultName string = keyVault.outputs.keyVaultName

@description('Path A test URL (client1 only).')
output client1Url string = 'https://${frontendHostName}/poc/client1'

@description('Path B test URL (client2 only).')
output client2Url string = 'https://${frontendHostName}/poc/client2'

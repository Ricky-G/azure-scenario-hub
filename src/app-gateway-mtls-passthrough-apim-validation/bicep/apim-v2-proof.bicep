// =====================================================================
// Premium v2 SKU-parity proof - orchestrator
// =====================================================================
// Deploys a standalone PUBLIC PremiumV2 API Management service alongside
// the existing classic-tier scenario, grants its managed identity access
// to the SAME Key Vault trust material, and applies the SAME dual-model
// validation policies + named values. Everything about the certificate
// trust decision is identical to the classic-tier deployment - only the
// APIM SKU differs - so any difference in behaviour would be attributable
// to the v2 policy engine.
//
// Reuses the existing modules kv-rbac.bicep and apim-config.bicep verbatim,
// which is itself part of the proof: the same IaC produces the same API,
// named values, and policies on a v2 tier.
// =====================================================================

@description('Azure region (must support PremiumV2).')
param location string = resourceGroup().location

@description('Short prefix for resource names.')
@minLength(3)
@maxLength(8)
param namePrefix string = 'mtlspoc'

@description('Publisher email for APIM notifications.')
param publisherEmail string = 'admin@example.com'

@description('Publisher organisation name.')
param publisherName string = 'Azure Scenario Hub'

@description('Name of the EXISTING Key Vault that holds the trust material.')
param keyVaultName string

@description('Certificate validation model the v2 policy enforces: pinned or chain.')
@allowed([
  'pinned'
  'chain'
])
param certValidationMode string = 'pinned'

@description('The v2 API Management SKU to deploy (PremiumV2 or StandardV2).')
@allowed([
  'PremiumV2'
  'StandardV2'
])
param apimSku string = 'PremiumV2'

var suffix = uniqueString(resourceGroup().id)
var apimV2Name = toLower('${namePrefix}apimv2${suffix}')
var vaultUri = 'https://${keyVaultName}${environment().suffixes.keyvaultDns}/'

var commonTags = {
  Environment: 'Development'
  Project: 'AzureScenarioHub'
  Scenario: 'AppGateway-mTLS-Passthrough-APIM'
  ManagedBy: 'Bicep'
  SkuProof: 'PremiumV2'
}

// The dual-model validation policies - the SAME files the classic tier uses.
var apiPolicyXml = loadTextContent('../apim/api-policy.xml')
var client1PolicyXml = loadTextContent('../apim/operation-client1-policy.xml')
var client2PolicyXml = loadTextContent('../apim/operation-client2-policy.xml')
var whoamiPolicyXml = loadTextContent('../apim/operation-whoami-policy.xml')

// Versionless KV secret identifiers (auto-refresh on rotation).
var rootSecretIdentifier = '${vaultUri}secrets/trusted-root-ca-der-b64'
var allowlistSecretIdentifier = '${vaultUri}secrets/client-cert-allowlist'

// 1. The Premium v2 (public) API Management service - the long pole (~minutes).
module apimV2 'modules/apim-v2.bicep' = {
  name: 'deploy-apim-v2'
  params: {
    location: location
    apimServiceName: apimV2Name
    publisherEmail: publisherEmail
    publisherName: publisherName
    apimSku: apimSku
    tags: commonTags
  }
}

// 2. Grant the v2 APIM identity read access to the existing Key Vault.
module kvRbac 'modules/kv-rbac.bicep' = {
  name: 'deploy-apim-v2-kv-rbac'
  params: {
    keyVaultName: keyVaultName
    principalId: apimV2.outputs.principalId
  }
}

// 3. The SAME API + named values + dual-model policies, on the v2 tier.
module apimConfig 'modules/apim-config.bicep' = {
  name: 'deploy-apim-v2-config'
  params: {
    apimName: apimV2.outputs.apimName
    rootSecretIdentifier: rootSecretIdentifier
    allowlistSecretIdentifier: allowlistSecretIdentifier
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

output apimV2Name string = apimV2.outputs.apimName
output apimV2Sku string = apimV2.outputs.apimSku
output apimV2GatewayUrl string = apimV2.outputs.gatewayUrl
output apiPath string = apimConfig.outputs.apiPath

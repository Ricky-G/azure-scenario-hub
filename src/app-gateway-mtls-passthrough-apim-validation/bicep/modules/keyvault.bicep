// =====================================================================
// Key Vault module (trust material store)
// =====================================================================
// Key Vault holds the trust material that API Management uses to make
// the certificate trust decision:
//   - trusted-root-ca-der-b64 : the trusted Root CA public certificate
//                               (DER, base64) used for issuer validation.
//   - client-cert-allowlist   : the per-client pinned-thumbprint allow
//                               list, formatted client1:THUMB|client2:THUMB
//
// APIM reads these through named values via its managed identity, so the
// policy sandbox never embeds the trust anchor directly.
// =====================================================================

@description('Azure region for the Key Vault.')
param location string

@description('Globally-unique Key Vault name.')
param keyVaultName string

@description('Tags applied to the Key Vault.')
param tags object

@description('Trusted Root CA certificate, DER encoded then base64 (single line).')
@secure()
param trustedRootCaDerB64 string

@description('Per-client pinned-thumbprint allow list: client1:THUMB|client2:THUMB.')
@secure()
param clientCertAllowlist string

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // POC: public access is left on so the deploy host and APIM's trusted
    // Microsoft service connectivity can reach the vault. Trust decisions
    // are still enforced in APIM, not by the vault network boundary.
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource rootSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'trusted-root-ca-der-b64'
  properties: {
    value: trustedRootCaDerB64
    contentType: 'text/plain; base64 DER of trusted Root CA'
  }
}

resource allowlistSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'client-cert-allowlist'
  properties: {
    value: clientCertAllowlist
    contentType: 'text/plain; client:thumbprint pairs'
  }
}

output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
// Versionless secret identifiers so APIM auto-refreshes on rotation.
output rootSecretIdentifier string = '${keyVault.properties.vaultUri}secrets/trusted-root-ca-der-b64'
output allowlistSecretIdentifier string = '${keyVault.properties.vaultUri}secrets/client-cert-allowlist'

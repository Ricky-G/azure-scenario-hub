// =====================================================================
// Key Vault RBAC module
// =====================================================================
// Grants the API Management system-assigned managed identity the
// "Key Vault Secrets User" role on the vault so its named values can
// resolve the trust material. Deployed AFTER APIM exists (its principal
// id is an input) and BEFORE the APIM named values are created.
// =====================================================================

@description('Name of the existing Key Vault.')
param keyVaultName string

@description('Principal (object) id of the APIM system-assigned identity.')
param principalId string

// Built-in role: Key Vault Secrets User
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, principalId, keyVaultSecretsUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = roleAssignment.id

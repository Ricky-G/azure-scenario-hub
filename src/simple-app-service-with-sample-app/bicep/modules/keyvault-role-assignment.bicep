// Module to add Key Vault access policy for a principal
// This module is required when the Key Vault is in a different resource group

@description('The name of the Key Vault')
param keyVaultName string

@description('The principal ID to grant access to')
param principalId string

@description('The tenant ID of the principal')
param tenantId string

// Reference to existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Add access policy to Key Vault (Get and List secrets only)
resource accessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
  }
}

// Outputs
@description('The Key Vault name')
output keyVaultName string = keyVault.name

@description('The access policy object ID')
output objectId string = principalId

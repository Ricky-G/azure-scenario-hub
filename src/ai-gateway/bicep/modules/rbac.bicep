// ============================================================================
// Module: rbac.bicep
// Grants APIM's system-assigned managed identity the "Cognitive Services User"
// role on the existing Foundry / Azure OpenAI account so the API-level policy
// can authenticate to the backend with `authentication-managed-identity`.
//
// Scoped to the Foundry resource group rather than the AI Gateway resource
// group because the Foundry already exists in the user's subscription.
// ============================================================================

@description('Name of the existing Foundry / Azure OpenAI account.')
param foundryAccountName string

@description('Object id (principalId) of APIM\'s system-assigned managed identity.')
param apimPrincipalId string

// Built-in role: Cognitive Services User
//   https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#cognitive-services-user
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'

resource foundry 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: foundryAccountName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundry
  // Deterministic GUID so re-deployments are idempotent.
  name: guid(foundry.id, apimPrincipalId, cognitiveServicesUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = roleAssignment.id

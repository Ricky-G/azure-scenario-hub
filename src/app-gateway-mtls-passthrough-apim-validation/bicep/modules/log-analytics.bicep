// =====================================================================
// Log Analytics module
// =====================================================================
// Central sink for Application Gateway and API Management diagnostics.
// The App Gateway access log is where the mutual-authentication server
// variables (including client_certificate_verification) can be observed,
// which is a key evidence source for this POC.
// =====================================================================

@description('Azure region for the workspace.')
param location string

@description('Name of the Log Analytics workspace.')
param workspaceName string

@description('Tags applied to the workspace.')
param tags object

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name

// ========================================
// Log Analytics Workspace Module
// ========================================
// Single workspace that acts as the destination for every diagnostic
// setting configured on the Application Gateway and API Management.

@description('Location for the Log Analytics Workspace.')
param location string

@description('Name of the Log Analytics Workspace.')
param workspaceName string

@description('Tags to apply to the resource.')
param tags object = {}

@description('Data retention in days for the workspace.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      // Use resource-level RBAC for log access.
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

@description('The resource ID of the Log Analytics Workspace.')
output workspaceId string = logAnalyticsWorkspace.id

@description('The name of the Log Analytics Workspace.')
output workspaceName string = logAnalyticsWorkspace.name

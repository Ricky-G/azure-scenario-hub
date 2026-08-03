@description('Azure region for the workspace gateway. It must match the API Management service primary region.')
param location string

@description('Name of the API Management workspace gateway.')
@minLength(1)
@maxLength(45)
param gatewayName string

@description('Tags applied to the workspace gateway.')
param tags object

@description('Resource IDs of the API Management workspaces served by this gateway.')
param workspaceResourceIds array

resource workspaceGateway 'Microsoft.ApiManagement/gateways@2024-05-01' = {
  name: gatewayName
  location: location
  tags: tags
  sku: {
    name: 'WorkspaceGatewayPremium'
    capacity: 1
  }
  properties: {
    virtualNetworkType: 'None'
  }
}

@batchSize(1)
resource workspaceConnections 'Microsoft.ApiManagement/gateways/configConnections@2024-06-01-preview' = [for (workspaceResourceId, index) in workspaceResourceIds: {
  parent: workspaceGateway
  name: take('ws-${index + 1}-${uniqueString(workspaceResourceId)}', 30)
  properties: {
    sourceId: workspaceResourceId
  }
}]

@description('Resource ID of the workspace gateway.')
output id string = workspaceGateway.id

@description('Name of the workspace gateway.')
output name string = workspaceGateway.name

@description('Default runtime hostname assigned to each workspace configuration connection, in input order.')
output defaultHostnames array = [for index in range(0, length(workspaceResourceIds)): workspaceConnections[index].properties.defaultHostname]

@description('Resource IDs of the workspace configuration connections.')
output connectionIds array = [for index in range(0, length(workspaceResourceIds)): workspaceConnections[index].id]

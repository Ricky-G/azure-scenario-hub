targetScope = 'subscription'

@description('Azure region for the scenario. Workspace gateways must match the API Management service primary region.')
param location string = 'westus'

@description('Resource group for workspace gateways and monitoring. A disposable APIM service is also created here when createApimService is true.')
param scenarioResourceGroupName string = 'rg-apim-federated-workspaces'

@description('Name of the API Management service. The name must be globally unique when createApimService is true.')
@minLength(1)
@maxLength(50)
param apimServiceName string

@description('Resource group containing an existing API Management service. Ignored when createApimService is true.')
param apimResourceGroupName string = ''

@description('Create a disposable Premium API Management service for the demo. Leave false to use an existing Premium service.')
param createApimService bool = false

@description('Install the demo service-level global policy. Enable only on a disposable APIM service because this replaces the existing global policy.')
param configureGlobalPolicy bool = false

@description('Workspace gateway topology. Dedicated creates one gateway per team; Shared places both teams on one gateway.')
@allowed([
  'Dedicated'
  'Shared'
])
param gatewayTopology string = 'Shared'

@description('Short prefix used to derive resource names.')
@minLength(3)
@maxLength(12)
param namePrefix string = 'apimwsdemo'

@description('API publisher email used only when createApimService is true.')
param publisherEmail string = 'admin@example.com'

@description('API publisher organization used only when createApimService is true.')
param publisherName string = 'Contoso'

@description('Optional object ID of the Microsoft Entra group or user representing the Data Science team.')
param dataScienceTeamPrincipalId string = ''

@description('Optional object ID of the Microsoft Entra group or user representing the Website Experience team.')
param websiteTeamPrincipalId string = ''

@description('Microsoft Entra principal type used for optional workspace role assignments.')
@allowed([
  'Group'
  'User'
  'ServicePrincipal'
])
param teamPrincipalType string = 'Group'

var scenarioName = 'APIM-Federated-Workspaces'
var targetApimResourceGroupName = createApimService ? scenarioResourceGroupName : apimResourceGroupName
var resourceSuffix = uniqueString(subscription().id, scenarioResourceGroupName)
var logAnalyticsWorkspaceName = take('${namePrefix}-law-${resourceSuffix}', 63)
var sharedGatewayName = take('${namePrefix}-shared-gw-${resourceSuffix}', 45)
var dataScienceGatewayName = take('${namePrefix}-ds-gw-${resourceSuffix}', 45)
var websiteGatewayName = take('${namePrefix}-web-gw-${resourceSuffix}', 45)
var commonTags = {
  Environment: 'Demo'
  Project: 'AzureScenarioHub'
  Scenario: scenarioName
  ManagedBy: 'Bicep'
}

resource scenarioResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: scenarioResourceGroupName
  location: location
  tags: commonTags
}

resource targetApimResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' existing = {
  name: targetApimResourceGroupName
}

module apimService 'modules/apim-service.bicep' = if (createApimService) {
  name: 'deploy-premium-apim'
  scope: scenarioResourceGroup
  params: {
    location: location
    apimServiceName: apimServiceName
    publisherEmail: publisherEmail
    publisherName: publisherName
    tags: commonTags
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-federated-monitoring'
  scope: scenarioResourceGroup
  params: {
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    tags: commonTags
  }
}

module workspaces 'modules/workspaces.bicep' = {
  name: 'deploy-team-workspaces'
  scope: targetApimResourceGroup
  params: {
    apimServiceName: apimServiceName
    logAnalyticsWorkspaceId: monitoring.outputs.id
    configureGlobalPolicy: configureGlobalPolicy
    dataScienceTeamPrincipalId: dataScienceTeamPrincipalId
    websiteTeamPrincipalId: websiteTeamPrincipalId
    teamPrincipalType: teamPrincipalType
  }
  dependsOn: [
    apimService
  ]
}

module sharedGateway 'modules/workspace-gateway.bicep' = if (gatewayTopology == 'Shared') {
  name: 'deploy-shared-workspace-gateway'
  scope: scenarioResourceGroup
  params: {
    location: location
    gatewayName: sharedGatewayName
    tags: union(commonTags, {
      GatewayTopology: 'Shared'
    })
    workspaceResourceIds: [
      workspaces.outputs.dataScienceWorkspaceId
      workspaces.outputs.websiteWorkspaceId
    ]
  }
}

module dataScienceGateway 'modules/workspace-gateway.bicep' = if (gatewayTopology == 'Dedicated') {
  name: 'deploy-data-science-workspace-gateway'
  scope: scenarioResourceGroup
  params: {
    location: location
    gatewayName: dataScienceGatewayName
    tags: union(commonTags, {
      Team: 'DataScience'
      GatewayTopology: 'Dedicated'
    })
    workspaceResourceIds: [
      workspaces.outputs.dataScienceWorkspaceId
    ]
  }
}

module websiteGateway 'modules/workspace-gateway.bicep' = if (gatewayTopology == 'Dedicated') {
  name: 'deploy-website-workspace-gateway'
  scope: scenarioResourceGroup
  params: {
    location: location
    gatewayName: websiteGatewayName
    tags: union(commonTags, {
      Team: 'WebsiteExperience'
      GatewayTopology: 'Dedicated'
    })
    workspaceResourceIds: [
      workspaces.outputs.websiteWorkspaceId
    ]
  }
}

@description('Resource group containing the scenario support resources.')
output scenarioResourceGroupName string = scenarioResourceGroup.name

@description('Resource group containing the API Management service.')
output apimResourceGroupName string = targetApimResourceGroupName

@description('Name of the API Management service.')
output apimServiceName string = apimServiceName

@description('Gateway topology deployed by the scenario.')
output gatewayTopology string = gatewayTopology

@description('Data Science workspace resource ID.')
output dataScienceWorkspaceId string = workspaces.outputs.dataScienceWorkspaceId

@description('Website Experience workspace resource ID.')
output websiteWorkspaceId string = workspaces.outputs.websiteWorkspaceId

@description('Runtime hostname for the Data Science workspace API.')
output dataScienceGatewayHostname string = gatewayTopology == 'Shared' ? sharedGateway!.outputs.defaultHostnames[0] : dataScienceGateway!.outputs.defaultHostnames[0]

@description('Runtime hostname for the Website Experience workspace API.')
output websiteGatewayHostname string = gatewayTopology == 'Shared' ? sharedGateway!.outputs.defaultHostnames[1] : websiteGateway!.outputs.defaultHostnames[0]

@description('Data Science API test URL.')
output dataScienceApiUrl string = 'https://${gatewayTopology == 'Shared' ? sharedGateway!.outputs.defaultHostnames[0] : dataScienceGateway!.outputs.defaultHostnames[0]}/ai-insights/score'

@description('Website Experience API test URL.')
output websiteApiUrl string = 'https://${gatewayTopology == 'Shared' ? sharedGateway!.outputs.defaultHostnames[1] : websiteGateway!.outputs.defaultHostnames[0]}/digital-experience/homepage'

@description('Log Analytics workspace resource ID for centralized and team-scoped queries.')
output logAnalyticsWorkspaceId string = monitoring.outputs.id

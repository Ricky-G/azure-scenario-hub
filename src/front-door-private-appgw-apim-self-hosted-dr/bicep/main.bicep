targetScope = 'resourceGroup'

@description('Azure region for regional resources. The scenario was designed for New Zealand North.')
param location string = resourceGroup().location

@description('Short prefix applied to resource names.')
@minLength(3)
@maxLength(10)
param namePrefix string = 'fdapimdr'

@description('Publisher email for API Management notifications.')
param publisherEmail string = 'admin@example.com'

@description('Publisher organization name shown in API Management.')
param publisherName string = 'Azure Scenario Hub'

@description('API Management SKU. Premium matches the target POC; Developer is offered only for lower-cost template development.')
@allowed([
  'Premium'
  'Developer'
])
param apimSku string = 'Premium'

@description('Azure Front Door managed Private Link region. Australia East is the nearest supported region to New Zealand North.')
param frontDoorPrivateLinkLocation string = 'australiaeast'

@description('Kubernetes minor version supported in the deployment region.')
param kubernetesVersion string = '1.34'

@description('Virtual machine size for the single POC AKS system node.')
param nodeVmSize string = 'Standard_D2s_v5'

var suffix = take(uniqueString(resourceGroup().id), 8)
var apimServiceName = toLower('${namePrefix}-apim-${suffix}')
var appGatewayName = '${namePrefix}-appgw'
var frontDoorProfileName = '${namePrefix}-afd-${suffix}'
var frontDoorEndpointName = toLower('${namePrefix}-${suffix}')
var testWebAppName = toLower('${namePrefix}-ui-${suffix}')
var aksBackendPrivateIp = '10.20.1.20'
var readerRoleDefinitionId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var commonTags = {
  Environment: 'Development'
  Project: 'AzureScenarioHub'
  Scenario: 'FrontDoor-Private-AppGateway-APIM-SelfHosted-DR'
  ManagedBy: 'Bicep'
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring'
  params: {
    location: location
    namePrefix: namePrefix
    tags: commonTags
  }
}

module network 'modules/network.bicep' = {
  name: 'deploy-network'
  params: {
    location: location
    namePrefix: namePrefix
    tags: commonTags
  }
}

module aks 'modules/aks.bicep' = {
  name: 'deploy-aks'
  params: {
    location: location
    namePrefix: namePrefix
    suffix: suffix
    aksSubnetId: network.outputs.aksSubnetId
    mockOnPremVnetName: network.outputs.mockOnPremVnetName
    aksSubnetName: network.outputs.aksSubnetName
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    kubernetesVersion: kubernetesVersion
    nodeVmSize: nodeVmSize
    tags: commonTags
  }
}

module apim 'modules/apim.bicep' = {
  name: 'deploy-apim'
  params: {
    location: location
    apimServiceName: apimServiceName
    publisherEmail: publisherEmail
    publisherName: publisherName
    apimSubnetId: network.outputs.apimSubnetId
    aksBackendPrivateIp: aksBackendPrivateIp
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    apimSku: apimSku
    tags: commonTags
  }
}

module appGateway 'modules/app-gateway.bicep' = {
  name: 'deploy-application-gateway'
  params: {
    location: location
    appGatewayName: appGatewayName
    appGatewaySubnetId: network.outputs.appGatewaySubnetId
    appGatewayPrivateLinkSubnetId: network.outputs.appGatewayPrivateLinkSubnetId
    appGatewayPublicIpId: network.outputs.appGatewayPublicIpId
    apimPrivateIp: apim.outputs.apimPrivateIpAddress
    apimGatewayHostname: apim.outputs.apimGatewayHostname
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    tags: commonTags
  }
}

module frontDoor 'modules/front-door.bicep' = {
  name: 'deploy-front-door'
  params: {
    profileName: frontDoorProfileName
    endpointName: frontDoorEndpointName
    appGatewayId: appGateway.outputs.appGatewayId
    appGatewayFrontendIpConfigurationName: appGateway.outputs.frontendIpConfigurationName
    apimGatewayHostname: apim.outputs.apimGatewayHostname
    privateLinkLocation: frontDoorPrivateLinkLocation
    drOriginHostname: aks.outputs.drPublicIpFqdn
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    tags: commonTags
  }
}

module testWebApp 'modules/test-web-app.bicep' = {
  name: 'deploy-test-web-app'
  params: {
    location: location
    namePrefix: namePrefix
    suffix: suffix
    frontDoorHostname: frontDoor.outputs.endpointHostname
    apimResourceId: apim.outputs.apimId
    apimServiceName: apim.outputs.apimName
    selfHostedGatewayName: apim.outputs.selfHostedGatewayName
    drOriginHostname: aks.outputs.drPublicIpFqdn
    tags: commonTags
  }
}

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

resource testWebAppApimReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(apimService.id, testWebAppName, readerRoleDefinitionId)
  scope: apimService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleDefinitionId)
    principalId: testWebApp.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Azure Front Door endpoint URL used by both test paths.')
output frontDoorUrl string = frontDoor.outputs.endpointUrl

@description('Happy-path test URL: Front Door to private App Gateway to managed APIM to AKS.')
output happyPathUrl string = frontDoor.outputs.happyUrl

@description('DR-path test URL: Front Door to the APIM self-hosted gateway on AKS to the in-cluster backend.')
output drPathUrl string = frontDoor.outputs.drUrl

@description('Hosted browser test UI URL.')
output testWebAppUrl string = testWebApp.outputs.webAppUrl

@description('Name of the App Service used by the browser test UI.')
output testWebAppName string = testWebApp.outputs.webAppName

@description('Name of the AKS cluster used as the mock on-premises environment.')
output aksClusterName string = aks.outputs.clusterName

@description('Static private IP used by the AKS Hello World internal load balancer.')
output aksBackendPrivateIp string = aksBackendPrivateIp

@description('Public IP resource name reserved for the APIM self-hosted gateway service.')
output drPublicIpName string = aks.outputs.drPublicIpName

@description('Public IP address reserved for the APIM self-hosted gateway service.')
output drPublicIpAddress string = aks.outputs.drPublicIpAddress

@description('Name of the internal API Management service.')
output apimServiceName string = apim.outputs.apimName

@description('Private IP address of the internal API Management service.')
output apimPrivateIpAddress string = apim.outputs.apimPrivateIpAddress

@description('Name of the API Management self-hosted gateway resource.')
output selfHostedGatewayName string = apim.outputs.selfHostedGatewayName

@description('Configuration endpoint used by the self-hosted gateway.')
output selfHostedGatewayConfigurationUri string = apim.outputs.selfHostedGatewayConfigurationUri

@description('Name of the private-only Application Gateway.')
output appGatewayName string = appGateway.outputs.appGatewayName

@description('Name of the Front Door Premium profile.')
output frontDoorProfileName string = frontDoor.outputs.profileName
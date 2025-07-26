targetScope='subscription'

@description('The location of the resources')
param location string = 'eastus'

@description('The name of the virtual network')
param vnetName string = 'myVnet'

@description('The name of the Bastion host')
param bastionHostName string = 'PrivateEventGridBastionHost'

@description('The name of the Event Grid topic')
param eventGridTopicName string = 'PrivateEventGridTopic12'

@description('The name of the Private Endpoint for the Event Grid topic')
param privateEndpointName string = 'PrivateEventGridTopic12PrivateEndpoint'

@description('The name of the storage account')
param storageAccountName string = 'logicappstorageaccount15'

@description('The name of the Log Analytics Workspace')
param logAnalyticsWorkspaceName string = 'LogAnalyticsWorkspace'

@description('The name of the file share to use for the logic apps')
param logicAppFileShareName string = 'logicappsfileshare'

@description('The name of the resource group')
param resourceGroupName string = 'rg-private-event-grids-test'

//Variables that are local to the deployment
var privateDNSZoneNameForEventGrid = 'privatelink.eventgrid.azure.net' // This is the private DNS zone for Event Grid

// Create the Resource Group
resource privateEventGridTestResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

// Deploy the Virtual Network
module vnet 'modules/vnet.bicep' = {
  name: 'vnetDeployment'
  params: {
    location: location
    vnetName: vnetName
  }
  scope: privateEventGridTestResourceGroup
}

// Deploy Application Insights and Log Analytics Workspace
module appInsights 'modules/app-insights.bicep' = {
  name: 'appInsightsDeploy'
  params: {
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    location: location
  }
  scope: privateEventGridTestResourceGroup
}

// Deploy the Bastion host
module bastion 'modules/bastion.bicep' = {
  name: 'bastionDeployment'
  dependsOn: [
    vnet
  ]
  params: {
    bastionHostName: bastionHostName
    location: location
    bastionSubnetId: vnet.outputs.bastionSubnetId
  }
  scope: privateEventGridTestResourceGroup
}

// Deploy the Private DNS Zone for Event Grid
module privateDNSZoneForEventGrid 'modules/private-dns-zone.bicep' = {
  name: 'privateDNSZoneForEventGridDeployment'  
  params: {
    name: privateDNSZoneNameForEventGrid
  }
  scope: privateEventGridTestResourceGroup
}

// Deploy the Event Grid Topic and Private Endpoint
module eventGridTopic 'modules/event-grid-topic.bicep' = {
  name: 'eventGridTopicDeployment'
  params: {
    eventGridTopicName: eventGridTopicName
    location: location
    vnetName: vnetName
    privateEndpointSubnetName: vnet.outputs.privateEndpointSubnetName
    privateEndpointName: privateEndpointName
  }
  scope: privateEventGridTestResourceGroup
}

// Deploy the Virtual Network Link for Event Grid
module virtualNetworkLinkForEventGrid 'modules/virtual-network-link.bicep' = {
  name: 'virtualNetworkLinkForEventGridDeployment'
  dependsOn: [
    eventGridTopic
    privateDNSZoneForEventGrid
  ]
  params: {
    privateDnsZoneName: privateDNSZoneNameForEventGrid
    vnetName: vnetName
  }
  scope: privateEventGridTestResourceGroup
}

// Deploy the Private DNS Group for Event Grid
module privateDnsGroupForEventGridPrivateEndPoint 'modules/private-dns-group.bicep' = {
  name: 'privateDnsGroupForEventGridPrivateEndPointDeployment'
  dependsOn: [
    eventGridTopic
    privateDNSZoneForEventGrid
    virtualNetworkLinkForEventGrid
  ]
  params: {
    privateDnsZoneConfigName: '${eventGridTopicName}config'
    privateDnsZoneId: privateDNSZoneForEventGrid.outputs.privateDnsZoneId
    privateEndpointName: eventGridTopic.outputs.eventGridTopidPrivateEndpointName
  }
  scope: privateEventGridTestResourceGroup
}

// Deploy the storage account
module storageAccount 'modules/storage-account.bicep' = {
  name: 'storageAccountDeployment'
  params: {
    storageAccountName: storageAccountName
    location: location
    fileShareName: logicAppFileShareName
  }
  scope: privateEventGridTestResourceGroup
}

// Deploy the app service plan
module appServicePlan 'modules/app-service-plan.bicep' = {
  name: 'appServicePlanDeployment'
  params: {
    appServicePlanName: 'myAppServicePlan'
    location: location
  }
  scope: privateEventGridTestResourceGroup
}

// Deploy the Logic App
module logicApp 'modules/logicapp.bicep' = {
  name: 'logicAppDeployment'
  dependsOn: [
    appServicePlan
  ]
  params: {
    logicAppName: 'PublishEventsToEventGridLogicApp'
    location: location
    storageAccountConnectionString: storageAccount.outputs.storageConnectionString
    appServicePlanId: appServicePlan.outputs.appServicePlanId
    appInsightsEndpoint: appInsights.outputs.appInsightsEndpoint
    appInsightsInstrumentationKey: appInsights.outputs.appInsightsInstrumentationKey
    subnetId: vnet.outputs.logicAppSubnetId
    fileShareName: logicAppFileShareName
  }
  scope: privateEventGridTestResourceGroup
}

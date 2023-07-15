targetScope='subscription'

@description('The location of the resources')
param location string = 'eastus'

@description('The name of the virtual network')
param vnetName string

@description('The name of the Bastion host')
param bastionHostName string

@description('The name of the Event Grid topic')
param eventGridTopicName string

@description('The name of the Private Endpoint for the Event Grid topic')
param privateEndpointName string

@description('The name of the resource group')
param resourceGroupName string = 'rg-private-event-grids-test'

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
module appInsightsModule 'modules/app-insights.bicep' = {
  name: 'appInsightsDeploy'
  params: {
    namePrefix: namePrefix
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

// Deploy the Event Grid Topic and Private Endpoint
module eventGridTopic 'modules/event-grid-topic.bicep' = {
  name: 'eventGridTopicDeployment'
  params: {
    eventGridTopicName: eventGridTopicName
    location: location
    vnetName: vnetName
    privateEndpointSubnetName: 'PrivateEndpointSubnet'
    privateEndpointName: privateEndpointName
  }
  scope: privateEventGridTestResourceGroup
}

// Deploy the storage account
module storageAccount 'modules/storage-account.bicep' = {
  name: 'storageAccountDeployment'
  params: {
    storageAccountName: 'logicappstorageaccount15'
    location: location
  }
  scope: privateEventGridTestResourceGroup
}

// Deploy the Logic App
module logicApp 'modules/logicapp-standard.bicep' = {
  name: 'logicAppDeployment'
  params: {
    logicAppName: 'PublishEventsToEventGridLogicApp'
    appServicePlanName: 'myAppServicePlan'
    location: location
    subnetId: vnet.outputs.logicAppSubnetId
    storageAccountConnectionString: storageAccount.outputs.connectionString
  }
  scope: privateEventGridTestResourceGroup
}

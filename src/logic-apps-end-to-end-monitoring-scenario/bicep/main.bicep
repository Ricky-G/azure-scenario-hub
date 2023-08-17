targetScope='subscription'

@description('The location of the resources')
param location string = 'eastus'

@description('The name of the resource group')
param resourceGroupName string = 'rg-integration-test'

@description('The name of the storage account')
param storageAccountForLogicAppsName string = 'integrationtststract23'

@description('The name of the storage account for testing the actual business logic and storing business data')
param storageAccountForTestingBusinessLogicName string = 'integrationtst2342'

@description('The name of the Log Analytics Workspace')
param logAnalyticsWorkspaceName string = 'IntegrationTestLogAnalyticsWorkspace'

@description('The name of the file share to use for the logic apps')
param logicAppFileShareName string = 'logicappsfileshare'

@description('The name of the app service plan')
param appServicePlanName string = 'integrationappserviceplan1'

// Create the Resource Group
resource integrationTestResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

// Deploy Application Insights and Log Analytics Workspace
module appInsights 'modules/app-insights.bicep' = {
  name: 'appInsightsDeploy'
  params: {
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    location: location
  }
  scope: integrationTestResourceGroup
}

// Deploy the storage account to be used for the logic apps resource (file share for the logic apps)
module storageAccountForLogicApps 'modules/storage-account.bicep' = {
  name: 'storageAccountForLogicAppsDeployment'
  params: {
    storageAccountName: storageAccountForLogicAppsName
    location: location
    fileShareName: logicAppFileShareName
  }
  scope: integrationTestResourceGroup
}

// Deploy the storage account that the workflows inside logic apps will use for business data
module storageAccountForTestingBusinessLogic 'modules/storage-account.bicep' = {
  name: 'storageAccountForTestingBusinessLogicDeployment'
  params: {
    storageAccountName: storageAccountForTestingBusinessLogicName
    location: location
    fileShareName: logicAppFileShareName
  }
  scope: integrationTestResourceGroup
}

// Deploy the app service plan
module appServicePlan 'modules/app-service-plan.bicep' = {
  name: 'appServicePlanDeployment'
  params: {
    appServicePlanName: appServicePlanName
    location: location
  }
  scope: integrationTestResourceGroup
}

// Deploy the Logic App
module logicApp 'modules/logicapp.bicep' = {
  name: 'logicAppDeployment'
  dependsOn: [
    appServicePlan
  ]
  params: {
    logicAppName: 'IntegrationcoreLogicApp'
    location: location
    storageAccountConnectionString: storageAccountForLogicApps.outputs.storageConnectionString
    appServicePlanId: appServicePlan.outputs.appServicePlanId
    appInsightsEndpoint: appInsights.outputs.appInsightsEndpoint
    appInsightsInstrumentationKey: appInsights.outputs.appInsightsInstrumentationKey
    fileShareName: logicAppFileShareName
  }
  scope: integrationTestResourceGroup
}

module CreateBlobContainerWorkflow 'logic-app-workflows/CreateBlobContainer.bicep' = {
  name: 'CreateBlobContainerDeployment'
  params: {
    logicAppName: logicApp.outputs.LogicAppName
    location: location
  }
  scope: integrationTestResourceGroup
}

module MQMessageOrchestratorStatefulWorkflow 'logic-app-workflows/MQMessageOrchestratorStateful.bicep' = {
  name: 'MQMessageOrchestratorStatefulDeployment'
  params: {
    logicAppName: logicApp.outputs.LogicAppName
    location: location
  }
  scope: integrationTestResourceGroup
}

module ProcessMQMessageWorkflow 'logic-app-workflows/ProcessMQMessage.bicep' = {
  name: 'ProcessMQMessageDeployment'
  params: {
    logicAppName: logicApp.outputs.LogicAppName
    location: location
  }
  scope: integrationTestResourceGroup
}

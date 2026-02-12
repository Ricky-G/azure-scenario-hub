targetScope = 'subscription'

@description('The location of the resources')
param location string = 'westus'

@description('Enable Confidential Compute for the Event Grid System Topic. Note: This is a preview feature with limited regional availability.')
param enableConfidentialCompute bool = false

@description('The name of the resource group')
param resourceGroupName string = 'rg-event-grid-confidential-compute'

@description('The name prefix for resources')
param namePrefix string = 'egcc'

// Variables
var storageAccountName = '${namePrefix}stor${uniqueString(subscription().subscriptionId, resourceGroupName)}'
var systemTopicName = '${namePrefix}-system-topic'

var commonTags = {
  Environment: 'Development'
  Project: 'AzureScenarioHub'
  Scenario: 'eventgrid-confidential-compute'
}

// Create the Resource Group
resource eventGridConfidentialComputeRG 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: commonTags
}

// Deploy the Storage Account (source for the System Topic)
module storageAccount 'modules/storage-account.bicep' = {
  name: 'storageAccountDeployment'
  scope: eventGridConfidentialComputeRG
  params: {
    storageAccountName: storageAccountName
    location: location
    tags: commonTags
  }
}

// Deploy the Event Grid System Topic with Confidential Compute enabled
module systemTopic 'modules/system-topic.bicep' = {
  name: 'systemTopicDeployment'
  scope: eventGridConfidentialComputeRG
  params: {
    systemTopicName: systemTopicName
    location: location
    sourceResourceId: storageAccount.outputs.storageAccountId
    topicType: 'Microsoft.Storage.StorageAccounts'
    enableConfidentialCompute: enableConfidentialCompute
    tags: commonTags
  }
}

// Outputs
output resourceGroupName string = eventGridConfidentialComputeRG.name
output storageAccountName string = storageAccount.outputs.storageAccountName
output systemTopicName string = systemTopic.outputs.systemTopicName
output systemTopicId string = systemTopic.outputs.systemTopicId
output confidentialComputeEnabled bool = enableConfidentialCompute

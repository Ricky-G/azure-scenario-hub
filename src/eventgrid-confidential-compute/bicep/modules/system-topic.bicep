@description('The name of the Event Grid System Topic')
param systemTopicName string

@description('The location of the System Topic')
param location string

@description('The resource ID of the source (e.g., Storage Account)')
param sourceResourceId string

@description('The type of the topic source (e.g., Microsoft.Storage.StorageAccounts)')
param topicType string

@description('Enable Azure Confidential Compute for the System Topic')
param enableConfidentialCompute bool = false

@description('Tags to apply to the System Topic')
param tags object = {}

// Create Event Grid System Topic with optional Confidential Compute
// Using API version 2025-07-15-preview which supports platformCapabilities.confidentialCompute
// Note: Confidential Compute is a preview feature with limited regional availability
resource systemTopic 'Microsoft.EventGrid/systemTopics@2025-07-15-preview' = {
  name: systemTopicName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    source: sourceResourceId
    topicType: topicType
    // Only include platformCapabilities when Confidential Compute is enabled
    // This is an immutable property set at resource creation time
    platformCapabilities: enableConfidentialCompute ? {
      confidentialCompute: {
        mode: 'Enabled'
      }
    } : null
  }
}

// Outputs
output systemTopicId string = systemTopic.id
output systemTopicName string = systemTopic.name
output systemTopicPrincipalId string = systemTopic.identity.principalId

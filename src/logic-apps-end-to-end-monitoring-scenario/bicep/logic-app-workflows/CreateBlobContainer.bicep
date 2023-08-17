@description('The location where the App Service plan will be deployed.')
param location string 

@description('The name of the Logic App.')
param logicAppName string

resource CreateBlobContainerWorkflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: '${logicAppName}-CreateBlobContainer'
  location: location
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      actions: {}
      contentVersion: '1.0.0.0'
      outputs: {}
      parameters: {}
      triggers: {}
    }
  }
}

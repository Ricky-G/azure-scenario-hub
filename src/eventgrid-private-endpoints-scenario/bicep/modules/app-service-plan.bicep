@description('The name of the App Service plan.')
param appServicePlanName string

@description('The location where the App Service plan will be deployed.')
param location string

resource appServicePlan 'Microsoft.Web/serverfarms@2021-02-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'WS1'
    tier: 'WorkflowStandard'
  }
}

output appServicePlanName string = appServicePlan.name
output appServicePlanId string = appServicePlan.id

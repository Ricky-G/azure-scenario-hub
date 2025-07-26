param logAnalyticsWorkspaceName string

@description('The location of the resource group. This must match the location of the app service.')
param location string = resourceGroup().location

var appInsightsName = '${logAnalyticsWorkspaceName}-ai'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource appinsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

output appInsightsName string = appinsights.name
output appInsightsId string = appinsights.id
output appInsightsInstrumentationKey string = appinsights.properties.InstrumentationKey
output appInsightsEndpoint string = appinsights.properties.ConnectionString
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

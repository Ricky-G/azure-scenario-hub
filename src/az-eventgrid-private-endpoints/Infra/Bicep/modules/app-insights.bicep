@minLength(3)
@maxLength(11)
param name string
param location string = resourceGroup().location

var appInsightsName = '${name}-ai'
var uniquelogAnalyticsWorkspaceName = '${name}${uniqueString(resourceGroup().id)}-ws'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
  name: uniquelogAnalyticsWorkspaceName
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

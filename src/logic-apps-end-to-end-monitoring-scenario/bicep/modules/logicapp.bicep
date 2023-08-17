@description('The location where the App Service plan will be deployed.')
param location string 

@description('The name of the Logic App.')
param logicAppName string

@description('The connection string for the storage account used by the Logic App.')
param storageAccountConnectionString string

@description('The instrumentation key for the Application Insights instance used by the Logic App.')
param appInsightsInstrumentationKey string

@description('The endpoint URL for the Application Insights instance used by the Logic App.')
param appInsightsEndpoint string

@description('The ID of the App Service plan used by the Logic App.')
param appServicePlanId string

@description('The name of the file share used by the Logic App.')
param fileShareName string

resource logicApp 'Microsoft.Web/sites@2021-02-01' = {
  name: logicAppName
  location: location
  kind: 'functionapp,workflowapp'
  identity: {
      type: 'SystemAssigned'
  }
  properties: {
    enabled: true    
    serverFarmId: appServicePlanId
    clientAffinityEnabled: true
    siteConfig: {
      // alwaysOn: true
      appSettings: [
        {
          name: 'APP_KIND'
          value: 'workflowApp'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsightsInstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsEndpoint
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__id'
          value: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__version'
          value: '[1.*, 2.0.0)'
        }
        {
          name: 'AzureWebJobsStorage'
          value: storageAccountConnectionString
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: storageAccountConnectionString
        }
        {
          name: 'WEBSITE_CONTENTOVERVNET'
          value: '1'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: fileShareName
        }
      ]
      cors: {
        allowedOrigins: [            
        ]
      }
    }
  } 
}

output LogicAppName string = logicApp.name

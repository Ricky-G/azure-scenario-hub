@description('Location for all resources')
param location string = resourceGroup().location

@description('Storage account name')
param storageAccountName string = 'stgunzip${uniqueString(resourceGroup().id)}'

@description('Storage account SKU')
param storageAccountSku string = 'Standard_LRS'

@description('Source container name for ZIP files')
param sourceContainerName string = 'zipped'

@description('Destination container name for extracted files')
param destinationContainerName string = 'unzipped'

@description('Function app name')
param functionAppName string = 'func-unzip-${uniqueString(resourceGroup().id)}'

@description('App service plan name')
param appServicePlanName string = 'asp-unzip-${uniqueString(resourceGroup().id)}'

@description('Application Insights name')
param applicationInsightsName string = 'appi-unzip-${uniqueString(resourceGroup().id)}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: storageAccountSku
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource sourceContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: sourceContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource destinationContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: destinationContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.9'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'SOURCE_CONTAINER_NAME'
          value: sourceContainerName
        }
        {
          name: 'DESTINATION_CONTAINER_NAME'
          value: destinationContainerName
        }
        {
          name: 'ZIP_PASSWORD'
          value: 'CHANGE_ME_IN_AZURE_PORTAL'
        }
      ]
    }
  }
}

output storageAccountName string = storageAccount.name
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
output sourceContainerName string = sourceContainer.name
output destinationContainerName string = destinationContainer.name
output functionAppName string = functionApp.name
output applicationInsightsName string = applicationInsights.name
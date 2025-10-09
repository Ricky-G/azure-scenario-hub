// Simple App Service with Python Sample App
// This template deploys an App Service Plan and App Service for hosting a Python web application

@description('The location for all resources')
param location string = resourceGroup().location

@description('The name prefix for all resources')
param namePrefix string = 'simpleapp'

@description('The environment name (e.g., dev, test, prod)')
param environment string = 'dev'

@description('The SKU name for the App Service Plan')
@allowed([
  'F1'  // Free
  'B1'  // Basic
  'B2'  // Basic
  'B3'  // Basic
  'S1'  // Standard
  'S2'  // Standard
  'S3'  // Standard
  'P1v2' // Premium v2
  'P2v2' // Premium v2
  'P3v2' // Premium v2
])
param appServicePlanSkuName string = 'B1'

@description('The Python version to use')
@allowed([
  '3.8'
  '3.9'
  '3.10'
  '3.11'
  '3.12'
])
param pythonVersion string = '3.11'

// Variables
var appServicePlanName = '${namePrefix}-asp-${environment}-${uniqueString(resourceGroup().id)}'
var appServiceName = '${namePrefix}-app-${environment}-${uniqueString(resourceGroup().id)}'

var commonTags = {
  Environment: environment
  Project: 'AzureScenarioHub'
  Scenario: 'SimpleAppServicePythonApp'
  ManagedBy: 'Bicep'
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: commonTags
  sku: {
    name: appServicePlanSkuName
  }
  kind: 'linux'
  properties: {
    reserved: true // Required for Linux
  }
}

// App Service (Web App)
resource appService 'Microsoft.Web/sites@2023-01-01' = {
  name: appServiceName
  location: location
  tags: commonTags
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|${pythonVersion}'
      alwaysOn: appServicePlanSkuName != 'F1' // AlwaysOn not available on Free tier
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      pythonVersion: pythonVersion
      appCommandLine: 'python -m gunicorn app:app' // Startup command for Flask app
      appSettings: [
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'ENABLE_ORYX_BUILD'
          value: 'true'
        }
      ]
    }
  }
}

// Outputs
@description('The name of the App Service Plan')
output appServicePlanName string = appServicePlan.name

@description('The name of the App Service')
output appServiceName string = appService.name

@description('The default hostname of the App Service')
output appServiceHostname string = appService.properties.defaultHostName

@description('The App Service URL')
output appServiceUrl string = 'https://${appService.properties.defaultHostName}'

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

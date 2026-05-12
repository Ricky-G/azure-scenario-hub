// Simple App Service with Python Sample App
// This template deploys an App Service Plan and App Service for hosting a Python web application
targetScope = 'subscription'

@description('The location for all resources')
@allowed([
  'australiaeast'
  'australiasoutheast'
  'southeastasia'
  'westus'
  'eastus2'
  'westus3'
  'eastasia'
  'newzealandnorth'
])
param location string = 'eastus2'

@description('The name prefix for all resources')
param namePrefix string = 'simpleapp'

@description('The environment name (e.g., dev, test, prod)')
param environment string = 'dev'

// ========================================================================================
// NEW: Resource Group Management
// ========================================================================================
@description('Create a new resource group (true) or use an existing one (false)')
param createNewResourceGroup bool = false

@description('The name of the resource group to create or use')
param resourceGroupName string = 'rg-${namePrefix}-${environment}'
// ========================================================================================

// ========================================================================================
// NEW: Existing App Service Plan Support
// ========================================================================================
@description('Use an existing App Service Plan instead of creating a new one')
param useExistingAppServicePlan bool = false

@description('The name of the existing App Service Plan (required if useExistingAppServicePlan is true)')
param existingAppServicePlanName string = ''

@description('The resource group name where the existing App Service Plan is located')
param existingAppServicePlanResourceGroup string = ''
// ========================================================================================

@description('The SKU name for the App Service Plan (only used when creating a new plan)')
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

@description('The Python version for the App Service')
@allowed([
  '3.8'
  '3.9'
  '3.10'
  '3.11'
  '3.12'
])
param pythonVersion string = '3.11'

// ========================================================================================
// NEW: VNet Integration Support
// ========================================================================================
@description('Enable VNet integration for outbound connectivity')
param useVnetIntegration bool = false

@description('The name of the existing Virtual Network (required if useVnetIntegration is true)')
param existingVNetName string = ''

@description('The resource group name where the existing VNet is located')
param existingVNetResourceGroup string = ''

@description('The name of the subnet to integrate with for outbound connectivity (required if useVnetIntegration is true)')
param existingSubnetName string = ''
// ========================================================================================

// Variables
var targetResourceGroupName = createNewResourceGroup ? resourceGroupName : resourceGroupName
var appServicePlanRG = useExistingAppServicePlan ? existingAppServicePlanResourceGroup : targetResourceGroupName
var vnetRG = useVnetIntegration ? existingVNetResourceGroup : targetResourceGroupName

var commonTags = {
  Environment: environment
  Project: 'AzureScenarioHub'
  Scenario: 'SimpleAppServicePythonApp'
  ManagedBy: 'Bicep'
}

// ========================================================================================
// NEW: Resource Group Creation (Conditional)
// ========================================================================================
resource newResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = if (createNewResourceGroup) {
  name: resourceGroupName
  location: location
  tags: commonTags
}
// ========================================================================================

// Deploy App Service resources into the resource group
module appServiceResources 'modules/app-service-resources.bicep' = {
  name: 'appServiceDeployment'
  scope: resourceGroup(targetResourceGroupName)
  params: {
    location: location
    namePrefix: namePrefix
    environment: environment
    useExistingAppServicePlan: useExistingAppServicePlan
    existingAppServicePlanName: existingAppServicePlanName
    existingAppServicePlanResourceGroup: appServicePlanRG
    appServicePlanSkuName: appServicePlanSkuName
    pythonVersion: pythonVersion
    useVnetIntegration: useVnetIntegration
    existingVNetName: existingVNetName
    existingVNetResourceGroup: vnetRG
    existingSubnetName: existingSubnetName
    commonTags: commonTags
  }
  dependsOn: [
    newResourceGroup
  ]
}

// Outputs
@description('The name of the resource group')
output resourceGroupName string = targetResourceGroupName

@description('The name of the App Service Plan (either created or existing)')
output appServicePlanName string = appServiceResources.outputs.appServicePlanName

@description('The name of the App Service')
output appServiceName string = appServiceResources.outputs.appServiceName

@description('The default hostname of the App Service')
output appServiceHostname string = appServiceResources.outputs.appServiceHostname

@description('The App Service URL')
output appServiceUrl string = appServiceResources.outputs.appServiceUrl

@description('Whether VNet integration is enabled')
output vnetIntegrationEnabled bool = useVnetIntegration

@description('The subnet ID used for VNet integration (if enabled)')
output vnetSubnetId string = appServiceResources.outputs.vnetSubnetId

// ========================================================================================
// NEW: Easy Auth (Azure AD SSO) Outputs
// ========================================================================================
@description('The App Registration Client ID (Application ID)')
output appRegistrationClientId string = appServiceResources.outputs.appRegistrationClientId

@description('The App Registration Object ID')
output appRegistrationObjectId string = appServiceResources.outputs.appRegistrationObjectId

@description('The App Registration Display Name')
output appRegistrationDisplayName string = appServiceResources.outputs.appRegistrationDisplayNameOutput
// ========================================================================================

// App Service Resources Module
// This module contains the actual App Service Plan and App Service resources
targetScope = 'resourceGroup'

@description('The location for all resources')
param location string

@description('The name prefix for all resources')
param namePrefix string

@description('The environment name')
param environment string

@description('Use an existing App Service Plan')
param useExistingAppServicePlan bool

@description('The name of the existing App Service Plan')
param existingAppServicePlanName string

@description('The resource group name where the existing App Service Plan is located')
param existingAppServicePlanResourceGroup string

@description('The SKU name for the App Service Plan')
param appServicePlanSkuName string

@description('The Python version for the App Service')
param pythonVersion string

@description('Enable VNet integration')
param useVnetIntegration bool

@description('The name of the existing Virtual Network')
param existingVNetName string

@description('The resource group name where the existing VNet is located')
param existingVNetResourceGroup string

@description('The name of the subnet')
param existingSubnetName string

@description('Common tags for all resources')
param commonTags object

// Variables
var appServicePlanName = '${namePrefix}-asp-${environment}-${uniqueString(resourceGroup().id)}'
var appServiceName = '${namePrefix}-app-${environment}-${uniqueString(resourceGroup().id)}'
var appRegDisplayName = '${namePrefix}-app-${environment}-appreg'

// ========================================================================================
// References to Existing Resources (Conditional)
// ========================================================================================
// Reference to existing App Service Plan (if using existing)
resource existingAppServicePlan 'Microsoft.Web/serverfarms@2023-01-01' existing = if (useExistingAppServicePlan) {
  name: existingAppServicePlanName
  scope: resourceGroup(existingAppServicePlanResourceGroup)
}

// Reference to existing Virtual Network (if using VNet integration)
resource existingVNet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = if (useVnetIntegration) {
  name: existingVNetName
  scope: resourceGroup(existingVNetResourceGroup)
}

// Reference to existing Subnet (if using VNet integration)
resource existingSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = if (useVnetIntegration) {
  name: existingSubnetName
  parent: existingVNet
}
// ========================================================================================

// App Service Plan (only created if not using existing)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = if (!useExistingAppServicePlan) {
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
    serverFarmId: useExistingAppServicePlan ? existingAppServicePlan.id : appServicePlan.id
    httpsOnly: true
    virtualNetworkSubnetId: useVnetIntegration ? existingSubnet.id : null
    siteConfig: {
      linuxFxVersion: 'PYTHON|${pythonVersion}'
      alwaysOn: appServicePlanSkuName != 'F1' // AlwaysOn not available on Free tier
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      pythonVersion: pythonVersion
      appCommandLine: 'python -m gunicorn app:app' // Startup command for Flask app
      vnetRouteAllEnabled: useVnetIntegration // Route all outbound traffic through VNet when integrated
      appSettings: [
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'ENABLE_ORYX_BUILD'
          value: 'true'
        }
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: useVnetIntegration ? '1' : '0'
        }
      ]
    }
  }
}

// ========================================================================================
// NEW: Easy Auth (Azure AD SSO) - App Registration via Deployment Script (CLI-based)
// ========================================================================================

// User-assigned managed identity for the deployment script
resource deploymentScriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-script-identity-${environment}'
  location: location
  tags: commonTags
}

// Create App Registration using Azure CLI deployment script
resource createAppRegistration 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${namePrefix}-create-appreg-${environment}'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deploymentScriptIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.50.0'
    timeout: 'PT30M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'APP_DISPLAY_NAME'
        value: appRegDisplayName
      }
      {
        name: 'REDIRECT_URI'
        value: 'https://${appService.properties.defaultHostName}/.auth/login/aad/callback'
      }
    ]
    scriptContent: '''
      # Check if app registration already exists
      existingApp=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv 2>/dev/null)
      
      if [ -n "$existingApp" ]; then
        echo "App Registration already exists with appId: $existingApp"
        appId=$existingApp
        objectId=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].id" -o tsv)
      else
        # Create the App Registration
        result=$(az ad app create \
          --display-name "$APP_DISPLAY_NAME" \
          --sign-in-audience "AzureADMyOrg" \
          --web-redirect-uris "$REDIRECT_URI" \
          --enable-id-token-issuance true \
          --required-resource-accesses '[{"resourceAppId":"00000003-0000-0000-c000-000000000000","resourceAccess":[{"id":"e1fe6dd8-ba31-4d61-89e7-88639da4683d","type":"Scope"}]}]' \
          --query "{appId:appId, objectId:id}" -o json)
        
        appId=$(echo $result | jq -r '.appId')
        objectId=$(echo $result | jq -r '.objectId')
        
        echo "Created App Registration with appId: $appId"
        
        # Create Service Principal for the app
        az ad sp create --id $appId || echo "Service Principal may already exist"
      fi
      
      # Output results for Bicep
      echo "{\"appId\": \"$appId\", \"objectId\": \"$objectId\", \"displayName\": \"$APP_DISPLAY_NAME\"}" > $AZ_SCRIPTS_OUTPUT_PATH
    '''
  }
}

// Configure Easy Auth on the App Service
resource appServiceAuthSettings 'Microsoft.Web/sites/config@2023-01-01' = {
  name: 'authsettingsV2'
  parent: appService
  properties: {
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: createAppRegistration.properties.outputs.appId
          openIdIssuer: 'https://sts.windows.net/${tenant().tenantId}/v2.0'
        }
        validation: {
          allowedAudiences: [
            'api://${createAppRegistration.properties.outputs.appId}'
            createAppRegistration.properties.outputs.appId
          ]
        }
      }
    }
    login: {
      tokenStore: {
        enabled: true
      }
    }
  }
}
// ========================================================================================

// Outputs
@description('The name of the App Service Plan')
output appServicePlanName string = useExistingAppServicePlan ? existingAppServicePlan.name : appServicePlan.name

@description('The name of the App Service')
output appServiceName string = appService.name

@description('The default hostname of the App Service')
output appServiceHostname string = appService.properties.defaultHostName

@description('The App Service URL')
output appServiceUrl string = 'https://${appService.properties.defaultHostName}'

@description('The subnet ID used for VNet integration')
output vnetSubnetId string = useVnetIntegration ? existingSubnet.id : ''

// ========================================================================================
// NEW: Easy Auth (Azure AD SSO) Outputs
// ========================================================================================
@description('The App Registration Client ID (Application ID)')
output appRegistrationClientId string = createAppRegistration.properties.outputs.appId

@description('The App Registration Object ID')
output appRegistrationObjectId string = createAppRegistration.properties.outputs.objectId

@description('The App Registration Display Name')
output appRegistrationDisplayNameOutput string = createAppRegistration.properties.outputs.displayName
// ========================================================================================

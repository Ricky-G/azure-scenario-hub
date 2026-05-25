// =====================================================================================
// App Service Easy Auth — Query String Round-Trip Demo
// -------------------------------------------------------------------------------------
// Deploys an App Service running Node.js with built-in authentication (Easy Auth)
// configured against Microsoft Entra ID. Demonstrates that custom query string
// parameters survive the full unauthenticated -> Entra sign-in -> redirect-back flow.
// =====================================================================================
targetScope = 'resourceGroup'

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Short prefix applied to all resource names for uniqueness.')
@minLength(3)
@maxLength(10)
param namePrefix string = 'easyauth'

@description('App Service Plan SKU. B1 is sufficient for this demo.')
@allowed([ 'B1', 'B2', 'S1', 'P1v3', 'P2v3', 'P3v3' ])
param appServicePlanSku string = 'B1'

@description('Entra app registration Application (client) ID. Created out-of-band by deploy script.')
param entraClientId string

@description('Entra tenant ID (GUID) the app registration belongs to.')
param entraTenantId string = subscription().tenantId

@description('Entra app registration client secret. Stored as a slot-sticky app setting.')
@secure()
param entraClientSecret string

// -------------------------------------------------------------------------------------
// Naming
// -------------------------------------------------------------------------------------
var uniqueSuffix     = uniqueString(resourceGroup().id)
var appServicePlanName = '${namePrefix}-plan-${uniqueSuffix}'
var webAppName         = '${namePrefix}-web-${uniqueSuffix}'

var commonTags = {
  Environment: 'Development'
  Project: 'AzureScenarioHub'
  Scenario: 'app-service-easy-auth'
  ManagedBy: 'Bicep'
}

// -------------------------------------------------------------------------------------
// App Service Plan (Linux)
// -------------------------------------------------------------------------------------
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: commonTags
  sku: {
    name: appServicePlanSku
  }
  kind: 'linux'
  properties: {
    reserved: true // required for Linux
  }
}

// -------------------------------------------------------------------------------------
// Web App
// -------------------------------------------------------------------------------------
resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  tags: commonTags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      alwaysOn: appServicePlanSku == 'B1' ? false : true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      appSettings: [
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~20'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        // Preserve URL fragments (anything after #) across the OAuth sign-in round trip.
        // Query strings are already preserved by default; this covers fragments too.
        {
          name: 'WEBSITE_AUTH_PRESERVE_URL_FRAGMENT'
          value: 'true'
        }
        // Client secret for the Entra app registration. Easy Auth reads this by name.
        {
          name: 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
          value: entraClientSecret
        }
      ]
    }
  }
}

// -------------------------------------------------------------------------------------
// Easy Auth v2 — Microsoft Entra identity provider
// -------------------------------------------------------------------------------------
// requireAuthentication=true + RedirectToLoginPage means any unauthenticated request
// is 302'd to /.auth/login/aad?post_login_redirect_url=<original URL incl. query string>.
// After Entra completes sign-in, Easy Auth redirects back to that exact original URL.
// -------------------------------------------------------------------------------------
resource authSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: webApp
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
      runtimeVersion: '~1'
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureactivedirectory'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          openIdIssuer: 'https://login.microsoftonline.com/${entraTenantId}/v2.0'
          clientId: entraClientId
          clientSecretSettingName: 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
        }
        login: {
          // No domain_hint here — we want to demo arbitrary query string round-trip,
          // not pre-populate the Entra sign-in page.
          loginParameters: []
        }
        validation: {
          allowedAudiences: [
            'api://${entraClientId}'
          ]
        }
      }
    }
    login: {
      tokenStore: {
        enabled: true
      }
      preserveUrlFragmentsForLogins: true
    }
    httpSettings: {
      requireHttps: true
      forwardProxy: {
        convention: 'NoProxy'
      }
    }
  }
}

// -------------------------------------------------------------------------------------
// Outputs
// -------------------------------------------------------------------------------------
output webAppName string = webApp.name
output webAppHostname string = webApp.properties.defaultHostName
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output authCallbackUrl string = 'https://${webApp.properties.defaultHostName}/.auth/login/aad/callback'
output resourceGroupName string = resourceGroup().name

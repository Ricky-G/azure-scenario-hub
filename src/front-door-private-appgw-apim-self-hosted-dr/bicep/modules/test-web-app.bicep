@description('Azure region for the App Service plan and web app.')
param location string

@description('Short prefix applied to resource names.')
param namePrefix string

@description('Deterministic suffix for the globally unique web app name.')
param suffix string

@description('Azure Front Door endpoint hostname used by the browser test UI.')
param frontDoorHostname string

@description('Resource ID of API Management used for live self-hosted gateway registration evidence.')
param apimResourceId string

@description('Name of API Management displayed in the evidence response.')
param apimServiceName string

@description('Name of the APIM self-hosted gateway verified by the test server.')
param selfHostedGatewayName string

@description('Public AKS origin hostname configured in Azure Front Door.')
param drOriginHostname string

@description('Tags applied to every resource.')
param tags object

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${namePrefix}-ui-plan'
  location: location
  tags: tags
  sku: {
    name: 'B1'
    tier: 'Basic'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: toLower('${namePrefix}-ui-${suffix}')
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      appCommandLine: 'node server.js'
      alwaysOn: true
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
          value: 'false'
        }
        {
          name: 'FRONT_DOOR_HOSTNAME'
          value: frontDoorHostname
        }
        {
          name: 'APIM_RESOURCE_ID'
          value: apimResourceId
        }
        {
          name: 'APIM_SERVICE_NAME'
          value: apimServiceName
        }
        {
          name: 'SELF_HOSTED_GATEWAY_NAME'
          value: selfHostedGatewayName
        }
        {
          name: 'DR_ORIGIN_HOSTNAME'
          value: drOriginHostname
        }
      ]
    }
  }
}

output webAppId string = webApp.id
output principalId string = webApp.identity.principalId
output webAppName string = webApp.name
output webAppHostname string = webApp.properties.defaultHostName
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
targetScope = 'subscription'

type apiDefinition = {
  name: string
  displayName: string
  path: string
  backendUrl: string
  spec: string
  policy: string
}

type backendSecretDefinition = {
  name: string
  placeholder: string
}

@description('True creates or updates the APIM resource group and its scenario tags; false requires an existing group and leaves its properties unchanged. APIM is deployed in either case.')
param createApimResourceGroup bool = true

@description('Resource group that will contain the APIM service, API, product, and subscription.')
param apimResourceGroupName string = 'rg-ai-gateway-poc'

@description('Azure region for APIM; also used when creating the APIM resource group.')
param apimLocation string = 'swedencentral'

@description('Short prefix for the globally unique APIM service name; changing it creates a different service.')
@minLength(3)
@maxLength(8)
param apimNamePrefix string = 'aigwpoc'

@description('Contact email shown as the publisher of the APIM service.')
param apimPublisherEmail string

@description('Default Azure OpenAI chat completions API version shown in the imported OpenAPI spec; clients must send a supported api-version on each request.')
param defaultOpenAiApiVersion string = '2024-10-21'

@description('Maximum requests per APIM subscription and API in each 60-second window.')
@minValue(1)
@maxValue(10000)
param requestsPerMinutePerSubscription int = 30

@description('APIs to publish, with their OpenAPI content, public route, backend URL, and optional API policy.')
param apiDefinitions apiDefinition[]

@description('Secret APIM named values to create once for authenticated backends; replace their placeholder values in the portal.')
param backendSecrets backendSecretDefinition[] = []

var tags = {
  Environment: 'Development'
  Project: 'AzureScenarioHub'
  Scenario: 'ai-gateway-poc'
  ManagedBy: 'Bicep'
}

resource apimResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = if (createApimResourceGroup) {
  name: apimResourceGroupName
  location: apimLocation
  tags: tags
}

module gateway 'modules/gateway.bicep' = {
  name: 'ai-gateway-poc'
  scope: resourceGroup(apimResourceGroupName)
  params: {
    location: apimLocation
    apimName: '${apimNamePrefix}-apim-${uniqueString(subscription().id, apimResourceGroupName)}'
    publisherEmail: apimPublisherEmail
    callsPerMinute: requestsPerMinutePerSubscription
    backendSecrets: backendSecrets
    tags: tags
  }
  dependsOn: [
    apimResourceGroup
  ]
}

module apis 'modules/api.bicep' = [for api in apiDefinitions: {
  name: 'api-${api.name}'
  scope: resourceGroup(apimResourceGroupName)
  params: {
    apimName: gateway.outputs.apimName
    productName: gateway.outputs.productName
    apiName: api.name
    apiDisplayName: api.displayName
    apiPath: api.path
    backendUrl: api.backendUrl
    spec: api.spec
    policyXml: api.policy
  }
}]

output resourceGroupName string = apimResourceGroupName
output apimName string = gateway.outputs.apimName
output gatewayUrl string = gateway.outputs.gatewayUrl
output subscriptionName string = gateway.outputs.subscriptionName
output defaultOpenAiApiVersion string = defaultOpenAiApiVersion

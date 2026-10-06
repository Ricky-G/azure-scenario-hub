using './main.bicep'

// true: create the APIM resource group, or update its tags if it already exists.
// false: the group must already exist in this subscription; leave its properties alone.
// Either way, deploy or update APIM inside that group. No Foundry resources are created.
param createApimResourceGroup = true

// Where APIM, its chat API, product, and demo subscription will be deployed.
param apimResourceGroupName = 'rg-ai-gateway-poc'

// Region of the APIM service (and of a newly created APIM resource group).
// For an existing group, this need not match the group's location.
param apimLocation = 'swedencentral'

// Prefix of the globally unique APIM service name; changing it creates another billable service.
param apimNamePrefix = 'aigwpoc'

// Valid email address used as the APIM publisher contact; replace this placeholder.
param apimPublisherEmail = 'you@example.com'

var openAiApiVersion = '2024-10-21'

// OpenAPI's suggested chat API version; clients still send ?api-version= on every call.
// Pick a version supported by the chosen Foundry deployment and request shape.
param defaultOpenAiApiVersion = openAiApiVersion

// Maximum calls per APIM subscription and API in a rolling 60-second window.
param requestsPerMinutePerSubscription = 30

// Create each backend credential as a secret named value with a harmless placeholder.
// Enter real keys under APIM > APIs > Named values after deployment; redeployment preserves them.
param backendSecrets = [
	{
		name: 'foundry-api-key'
		placeholder: 'REPLACE_WITH_FOUNDRY_API_KEY'
	}
]

// Add an entry for each OpenAPI file to publish. File paths are relative to this file.
// Give each API a unique name and path; set policy: '' to use only the shared service policy.
// Backend URLs are non-secret. Keep credentials in APIM secret named values, not here.
param apiDefinitions = [
	{
		name: 'azure-openai'
		displayName: 'Azure OpenAI Chat Completions'
		path: 'ai'
		backendUrl: 'https://ai-foundary-sweden-central.cognitiveservices.azure.com/'
		spec: replace(loadTextContent('../apis/openai.yaml'), '__DEFAULT_OPENAI_API_VERSION__', openAiApiVersion)
		policy: loadTextContent('../policies/openai.xml')
	}
	{
		name: 'star-wars'
		displayName: 'Star Wars API'
		path: 'starwars'
		backendUrl: 'https://swapi.info/api'
		spec: loadTextContent('../apis/starwars.yaml')
		policy: loadTextContent('../policies/starwars.xml')
	}
]

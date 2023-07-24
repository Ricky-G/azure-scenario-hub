# To deploy the core infrastructure
az deployment sub create --location eastus --name 'private-eventgrid-endpoint-deployment' --template-file main.bicep --parameters `
  location='eastus' `
  vnetName='myVNet' `
  bastionHostName='PrivateEventGridBastionHost' `
  eventGridTopicName='PrivateEventGridTopic12' `
  privateEndpointName='PrivateEventGridTopic12PrivateEndpoint'

# Deploy APIM with one API to act as Event Grid subscriber
az deployment group create --name apimDeployment --resource-group rg-private-event-grids-test --template-file apim.bicep --parameters apimName='PrivateEventGridTestApim' apimPublisherName='TestPublisher' apimPublisherEmail='ricky.gummadi@microsoft.com' location='eastus' backendUrl='https://bing.com/'

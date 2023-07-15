az deployment sub create --location eastus --name 'private-eventgrid-endpoint-deployment' --template-file main.bicep --parameters `
  location='eastus' `
  vnetName='myVNet' `
  bastionHostName='PrivateEventGridBastionHost' `
  eventGridTopicName='PrivateEventGridTopic12' `
  privateEndpointName='PrivateEventGridTopic12PrivateEndpoint'
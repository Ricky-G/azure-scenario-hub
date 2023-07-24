@description('The location where the APIM instance will be deployed.')
param location string 

@description('The name of the APIM instance.')
param apimName string

@description('The publisher name for the APIM instance.')
param apimPublisherName string

@description('The publisher email for the APIM instance.')
param apimPublisherEmail string

@description('The URL of the backend service that the API Management instance will be hooked up to.')
param backendUrl string

resource apim 'Microsoft.ApiManagement/service@2020-06-01-preview' = {
  name: apimName
  location: location
  sku: {
    name: 'Developer' // Change this as per your requirement
    capacity: 1
  }
  properties: {
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
  }
}

resource api 'Microsoft.ApiManagement/service/apis@2020-06-01-preview' = {
  name: '${apim.name}/EventGridSubscriber'
  properties: {
    displayName: 'Event Grid Subscriber'
    path: 'eventgridsubscriber'
    protocols: [
      'https'
    ]
    serviceUrl: backendUrl
    type: 'http'
  }
}

resource operation 'Microsoft.ApiManagement/service/apis/operations@2020-06-01-preview' = {
  name: '${api.name}/postevent'
  properties: {
    displayName: 'Post Event'
    method: 'POST'
    urlTemplate: '/'
    description: 'Endpoint for receiving Event Grid events'
  }
}

output ApimName string = apim.name
output ApiName string = api.name
output OperationName string = operation.name

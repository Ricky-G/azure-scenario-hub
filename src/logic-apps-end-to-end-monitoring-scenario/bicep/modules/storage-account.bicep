// Parameters
@description('The name of the storage account.')
param storageAccountName string

@description('The SKU of the storage account.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
  'Premium_ZRS'
  'Standard_GZRS'
  'Standard_RAGZRS'
])
param storageSKU string = 'Standard_LRS'

@description('The location where the storage account will be deployed.')
param location string

@description('The name of the file share. Leave empty if no file share is required.')
param fileShareName string = ''

// Resources
resource stg 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageSKU
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
  }
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-04-01' = if (!empty(fileShareName)) {
  name: '${stg.name}/default/${fileShareName}'
}

// Outputs
var blobStorageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${stg.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(stg.id, stg.apiVersion).keys[0].value}'
output storageName string = stg.name
output storageEndpoint string = stg.properties.primaryEndpoints.blob
output fileShareNameOutput string = fileShareName == '' ? 'No file share created' : fileShare.name
output storageConnectionString string = blobStorageConnectionString

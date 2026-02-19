// ========================================
// APIM Monitoring Workbook Module
// ========================================
// Creates a comprehensive Azure Workbook for monitoring API Management

@description('The location for the workbook')
param location string

@description('The name of the API Management service to monitor')
param apimServiceName string

@description('The resource ID of the API Management service')
param apimResourceId string

@description('The name of the workbook')
param workbookName string = 'APIM-Monitoring-Dashboard'

@description('Tags to apply to the workbook')
param tags object = {}

// ============
// Variables
// ============

var workbookDisplayName = 'APIM Monitoring Dashboard - ${apimServiceName}'
var workbookId = guid(resourceGroup().id, workbookName)

// Load the workbook template
var workbookContent = loadTextContent('workbook-template.json')

// ============
// Workbook Resource
// ============

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: workbookId
  location: location
  tags: union(tags, {
    'hidden-title': workbookDisplayName
  })
  kind: 'shared'
  properties: {
    displayName: workbookDisplayName
    serializedData: workbookContent
    version: '1.0'
    sourceId: apimResourceId
    category: 'API Management'
  }
}

// ============
// Outputs
// ============

@description('The resource ID of the workbook')
output workbookId string = workbook.id

@description('The name of the workbook')
output workbookName string = workbook.name

@description('The workbook display name')
output workbookDisplayName string = workbookDisplayName

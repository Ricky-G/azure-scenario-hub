// =====================================================================
// API Management module (Developer tier, Internal VNet)
// =====================================================================
// APIM is the trust anchor in this design. It is deployed in Internal
// VNet mode so it is reachable ONLY from inside the virtual network
// (i.e. from the Application Gateway subnet) - this network lockdown is
// one of the two load-bearing controls against header spoofing.
//
// NOTE: Developer-tier Internal VNet provisioning takes ~30-45 minutes.
// =====================================================================

@description('Azure region for API Management.')
param location string

@description('Globally-unique API Management service name.')
param apimServiceName string

@description('Publisher email for APIM notifications.')
param publisherEmail string

@description('Publisher organisation name.')
param publisherName string

@description('Resource id of the APIM subnet.')
param apimSubnetId string

@description('Resource id of the Standard public IP for the APIM control plane.')
param apimPublicIpId string

@description('Resource id of the Log Analytics workspace for diagnostics.')
param logAnalyticsWorkspaceId string

@description('Tags applied to API Management.')
param tags object

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimServiceName
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    // Internal mode = APIM gateway is only reachable from within the VNet.
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
    // stv2 platform requires a Standard public IP even in Internal mode.
    publicIpAddressId: apimPublicIpId
  }
}

// Stream the APIM gateway logs to Log Analytics for evidence capture.
resource apimDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'apim-diagnostics'
  scope: apim
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output apimName string = apim.name
output principalId string = apim.identity.principalId
// Private IP inside the VNet - only populated after Internal provisioning.
output privateIpAddress string = apim.properties.privateIPAddresses[0]
output gatewayHostName string = '${apim.name}.azure-api.net'

// =====================================================================
// API Management module - Premium v2 (PUBLIC), for the SKU-parity proof
// =====================================================================
// This is a SECOND, standalone APIM used only to prove that the client-
// certificate validation logic behaves identically on an API Management
// **v2** tier (PremiumV2) as it does on the classic Developer tier.
//
// It is deliberately PUBLIC (no VNet injection): the thing under test is
// the v2 policy engine's handling of the forwarded `X-Client-Cert` header,
// not the network path (which is tier-independent and already proven on
// the classic-tier stack). Because validation is driven entirely by the
// forwarded header - never by `context.Request.Certificate` - the v2
// "certificate renegotiation is not supported" limitation does not apply.
//
// v2 tiers provision in minutes (vs ~30-45 min for classic Internal VNet).
// =====================================================================

@description('Azure region for API Management (must support PremiumV2).')
param location string

@description('Globally-unique API Management service name.')
param apimServiceName string

@description('Publisher email for APIM notifications.')
param publisherEmail string

@description('Publisher organisation name.')
param publisherName string

@description('The v2 API Management SKU to deploy (PremiumV2 or StandardV2). Both share the same v2 policy engine and the same v2-tier certificate limitations.')
@allowed([
  'PremiumV2'
  'StandardV2'
])
param apimSku string = 'PremiumV2'

@description('Tags applied to API Management.')
param tags object

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: apimServiceName
  location: location
  tags: tags
  sku: {
    // The v2 tier under test. PremiumV2/StandardV2 share the same v2 policy
    // engine and the same documented v2-tier cert limitations - which this
    // scenario sidesteps by validating the forwarded header.
    name: apimSku
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    // Public inbound - no virtualNetworkType / no publicIpAddressId.
  }
}

@description('Name of the deployed v2 API Management service.')
output apimName string = apim.name

@description('The v2 SKU that was deployed.')
output apimSku string = apim.sku.name

@description('System-assigned identity principal id (for Key Vault RBAC).')
output principalId string = apim.identity.principalId

@description('Public gateway URL of the v2 API Management service.')
output gatewayUrl string = apim.properties.gatewayUrl

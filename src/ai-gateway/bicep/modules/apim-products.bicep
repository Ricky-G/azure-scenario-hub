// ============================================================================
// Module: apim-products.bicep
// Creates one APIM Product per business app / use-case, attaches BOTH the
// AUE and Global AOAI APIs to it (so a single subscription key works for
// either route), applies the product policy template (with `appId` /
// `useCase` / per-product TPM substituted) and creates an opinionated demo
// subscription so the test harness can pick up keys straight from the
// deployment outputs.
// ============================================================================

@description('Existing APIM service name.')
param apimServiceName string

@description('Names of the AOAI APIs to attach each product to (one or more).')
param apiNames array

@description('Definition of the products / use-cases to onboard.')
param products array

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

var productPolicyTemplate = loadTextContent('../../policies/product-policy.xml')

resource demoProducts 'Microsoft.ApiManagement/service/products@2024-05-01' = [for product in products: {
  parent: apim
  name: product.id
  properties: {
    displayName: product.displayName
    description: product.description
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}]

// Attach every product to the first API and (if present) the second API.
// Bicep can't express a true cartesian product cleanly without flattening,
// so we hard-wire two link resources that cover the demo's needs.
resource productApiLinks 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = [for (product, pIdx) in products: {
  parent: demoProducts[pIdx]
  name: apiNames[0]
}]

resource productApiLinksExtra 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = [for (product, pIdx) in products: if (length(apiNames) > 1) {
  parent: demoProducts[pIdx]
  name: apiNames[1]
}]

resource productPolicies 'Microsoft.ApiManagement/service/products/policies@2024-05-01' = [for (product, pIdx) in products: {
  parent: demoProducts[pIdx]
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: replace(replace(replace(productPolicyTemplate, '__APP_ID__', product.appId), '__USE_CASE__', product.useCase), '__TPM_LIMIT__', string(product.tpmLimit))
  }
  dependsOn: [
    productApiLinks
  ]
}]

resource productSubscriptions 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = [for (product, pIdx) in products: {
  parent: apim
  name: '${product.id}-demo-sub'
  properties: {
    displayName: '${product.displayName} demo subscription'
    scope: '/products/${demoProducts[pIdx].id}'
    state: 'active'
    allowTracing: true
  }
  dependsOn: [
    productApiLinks
    productApiLinksExtra
  ]
}]

output productNames array = [for (product, pIdx) in products: demoProducts[pIdx].name]
output subscriptionResourceIds array = [for (product, pIdx) in products: productSubscriptions[pIdx].id]

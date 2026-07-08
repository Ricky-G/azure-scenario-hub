// =====================================================================
// API Management configuration module
// =====================================================================
// Creates the trust material named values (sourced from Key Vault via the
// APIM managed identity), the demo API with two per-client operations, and
// attaches the validation/authorization policies. Deployed AFTER the APIM
// managed identity has been granted Key Vault access.
// =====================================================================

@description('Name of the existing API Management service.')
param apimName string

@description('Versionless KV secret id for the trusted Root CA (DER, base64).')
param rootSecretIdentifier string

@description('Versionless KV secret id for the per-client allow list.')
param allowlistSecretIdentifier string

@description('API-scope inbound policy XML.')
param apiPolicyXml string

@description('Operation policy XML for client1 (path A).')
param client1PolicyXml string

@description('Operation policy XML for client2 (path B).')
param client2PolicyXml string

@description('Operation policy XML for the model-neutral /whoami probe.')
param whoamiPolicyXml string

@description('Active certificate validation model: pinned (thumbprint allow list) or chain (Root CA signature).')
@allowed([
  'pinned'
  'chain'
])
param certValidationMode string = 'pinned'

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apimName
}

// Trust material named values (resolved from Key Vault at runtime) --------
resource nvRoot 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apim
  name: 'trusted-root-ca-der-b64'
  properties: {
    displayName: 'trusted-root-ca-der-b64'
    secret: true
    keyVault: {
      secretIdentifier: rootSecretIdentifier
    }
  }
}

resource nvAllow 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apim
  name: 'client-cert-allowlist'
  properties: {
    displayName: 'client-cert-allowlist'
    secret: true
    keyVault: {
      secretIdentifier: allowlistSecretIdentifier
    }
  }
}

// Selects which validation model the API policy enforces (plain, not secret).
resource nvMode 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apim
  name: 'cert-validation-mode'
  properties: {
    displayName: 'cert-validation-mode'
    value: certValidationMode
    secret: false
  }
}

// Demo API ----------------------------------------------------------------
resource api 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apim
  name: 'mtls-poc'
  properties: {
    displayName: 'mTLS Passthrough POC'
    path: 'poc'
    protocols: [
      'https'
    ]
    // Auth is by client certificate, not subscription key.
    subscriptionRequired: false
  }
}

// API-scope policy performs certificate parsing + trust validation.
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: apiPolicyXml
  }
  // Named values must exist before a policy that references {{...}} is set.
  dependsOn: [
    nvRoot
    nvAllow
    nvMode
  ]
}

resource opClient1 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'client1'
  properties: {
    displayName: 'Client1 - Path A'
    method: 'GET'
    urlTemplate: '/client1'
  }
}

resource opClient1Policy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-05-01-preview' = {
  parent: opClient1
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: client1PolicyXml
  }
  dependsOn: [
    apiPolicy
  ]
}

resource opClient2 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'client2'
  properties: {
    displayName: 'Client2 - Path B'
    method: 'GET'
    urlTemplate: '/client2'
  }
}

resource opClient2Policy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-05-01-preview' = {
  parent: opClient2
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: client2PolicyXml
  }
  dependsOn: [
    apiPolicy
  ]
}

// Model-neutral trust probe: 200 for ANY cert APIM trusts under the active
// model (no per-client authz). Shows the pinned-vs-chain difference for a
// CA-signed-but-unlisted certificate (client3).
resource opWhoami 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'whoami'
  properties: {
    displayName: 'Whoami - model-neutral trust probe'
    method: 'GET'
    urlTemplate: '/whoami'
  }
}

resource opWhoamiPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-05-01-preview' = {
  parent: opWhoami
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: whoamiPolicyXml
  }
  dependsOn: [
    apiPolicy
  ]
}

output apiPath string = api.properties.path

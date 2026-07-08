// =====================================================================
// Application Gateway module (WAF_v2, mTLS PASSTHROUGH)
// =====================================================================
// This is the heart of the POC. The Application Gateway:
//   - Terminates client TLS on an HTTPS listener (self-signed server
//     cert for the POC) and requests a CLIENT certificate.
//   - Runs the SSL profile in PASSTHROUGH mode
//     (clientAuthConfiguration.verifyClientAuthMode = 'Passthrough').
//     In passthrough the gateway does NOT validate the CA/chain and does
//     NOT terminate the connection if the client cert is missing/invalid.
//   - Forwards the client cert (and its mutual-auth server variables) to
//     APIM using a header-rewrite rule that SETS (overwrites) the headers
//     so a client can never inject its own values.
//   - Keeps WAF_v2 enabled (Prevention) via an associated WAF policy.
//
// Passthrough requires API version 2025-03-01 or later and is NOT
// configurable via CLI/PowerShell - only ARM/Bicep/Portal.
// =====================================================================

@description('Azure region for the Application Gateway.')
param location string

@description('Name of the Application Gateway.')
param appGatewayName string

@description('Resource id of the App Gateway subnet.')
param appGwSubnetId string

@description('Resource id of the App Gateway public IP.')
param appGwPublicIpId string

@description('Base64-encoded PFX for the frontend server certificate.')
@secure()
param serverCertData string

@description('Password for the frontend server certificate PFX.')
@secure()
param serverCertPassword string

@description('Private IP address of the Internal-mode APIM gateway.')
param apimPrivateIp string

@description('APIM gateway host name used for SNI / host header / probe.')
param apimGatewayHost string

@description('Resource id of the associated WAF policy.')
param wafPolicyId string

@description('Application Gateway SKU. WAF_v2 for the real scenario; Standard_v2 only for isolation testing.')
@allowed([
  'WAF_v2'
  'Standard_v2'
])
param skuTier string = 'WAF_v2'

@description('Resource id of the Log Analytics workspace for diagnostics.')
param logAnalyticsWorkspaceId string

@description('Tags applied to the Application Gateway.')
param tags object

var appGwId = resourceId('Microsoft.Network/applicationGateways', appGatewayName)

// Sub-resource names (kept as variables so ids stay readable).
var feIpName = 'appgw-feip'
var fePortName = 'port-443'
var serverCertName = 'appgw-server-cert'
var sslProfileName = 'mtls-passthrough'
var listenerName = 'https-listener'
var probeName = 'apim-status-probe'
var backendPoolName = 'apim-backend-pool'
var backendSettingsName = 'apim-https-settings'
var rewriteSetName = 'forward-client-cert'
var routingRuleName = 'https-routing-rule'


resource appGateway 'Microsoft.Network/applicationGateways@2025-03-01' = {
  name: appGatewayName
  location: location
  tags: tags
  properties: {
    sku: {
      name: skuTier
      tier: skuTier
      capacity: 1
    }
    // Gateway-wide SSL policy. This MUST be the same generation as the
    // listener SSL profile's policy below - Application Gateway rejects
    // mixing a "newer" profile policy with the implicit "older" default
    // (AppGwSslPolicy20150501). Both are pinned to the 2022 policy.
    sslPolicy: {
      policyType: 'Predefined'
      policyName: 'AppGwSslPolicy20220101'
    }
    gatewayIPConfigurations: [
      {
        name: 'appgw-ipconfig'
        properties: {
          subnet: {
            id: appGwSubnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: feIpName
        properties: {
          publicIPAddress: {
            id: appGwPublicIpId
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: fePortName
        properties: {
          port: 443
        }
      }
    ]
    sslCertificates: [
      {
        name: serverCertName
        properties: {
          data: serverCertData
          password: serverCertPassword
        }
      }
    ]
    // ---- PASSTHROUGH mTLS: the single most important setting ----------
    // Matches Microsoft's canonical passthrough ARM template. The SSL
    // profile carries an explicit `id` (required so the listener's
    // cross-reference resolves at the data plane) and its own sslPolicy
    // (the data-plane validator requires the profile to specify either an
    // sslPolicy or trustedClientCertificates). The gateway-wide sslPolicy
    // above is pinned to the SAME predefined policy to avoid a mismatch.
    sslProfiles: [
      {
        name: sslProfileName
        id: '${appGwId}/sslProfiles/${sslProfileName}'
        properties: {
          clientAuthConfiguration: {
            verifyClientAuthMode: 'Passthrough'
            verifyClientCertIssuerDN: false
            verifyClientRevocation: 'None'
          }
          sslPolicy: {
            policyType: 'Predefined'
            policyName: 'AppGwSslPolicy20220101'
          }
        }
      }
    ]
    httpListeners: [
      {
        name: listenerName
        properties: {
          frontendIPConfiguration: {
            id: '${appGwId}/frontendIPConfigurations/${feIpName}'
          }
          frontendPort: {
            id: '${appGwId}/frontendPorts/${fePortName}'
          }
          protocol: 'Https'
          // Basic (non-SNI) HTTPS listener, matching Microsoft's canonical
          // passthrough template. A multi-site listener (hostName +
          // requireServerNameIndication) drops the client-auth handshake
          // even when the client sends the matching SNI. The client still
          // verifies the server cert CN (api.mtls-poc.local) on its side.
          sslCertificate: {
            id: '${appGwId}/sslCertificates/${serverCertName}'
          }
          sslProfile: {
            id: '${appGwId}/sslProfiles/${sslProfileName}'
          }
        }
      }
    ]
    probes: [
      {
        name: probeName
        properties: {
          protocol: 'Https'
          host: apimGatewayHost
          path: '/status-0123456789abcdef'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: false
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: backendPoolName
        properties: {
          backendAddresses: [
            {
              // Reach Internal-mode APIM directly on its private IP.
              ipAddress: apimPrivateIp
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: backendSettingsName
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          // Explicit host header/SNI so the azure-api.net backend cert
          // (public-CA signed, trusted by App Gateway v2) validates.
          hostName: apimGatewayHost
          pickHostNameFromBackendAddress: false
          requestTimeout: 60
          probe: {
            id: '${appGwId}/probes/${probeName}'
          }
        }
      }
    ]
    // ---- Forward the TLS-derived client cert to APIM ------------------
    // Every header is SET (overwrite) from an App Gateway server variable,
    // so any client-supplied X-Client-Cert* header is discarded.
    rewriteRuleSets: [
      {
        name: rewriteSetName
        properties: {
          rewriteRules: [
            {
              name: 'set-client-cert-headers'
              ruleSequence: 100
              actionSet: {
                requestHeaderConfigurations: [
                  {
                    headerName: 'X-Client-Cert'
                    headerValue: '{var_client_certificate}'
                  }
                  {
                    headerName: 'X-Client-Cert-Subject'
                    headerValue: '{var_client_certificate_subject}'
                  }
                  {
                    headerName: 'X-Client-Cert-Issuer'
                    headerValue: '{var_client_certificate_issuer}'
                  }
                  {
                    headerName: 'X-Client-Cert-Fingerprint'
                    headerValue: '{var_client_certificate_fingerprint}'
                  }
                  {
                    headerName: 'X-Client-Cert-Serial'
                    headerValue: '{var_client_certificate_serial}'
                  }
                  {
                    headerName: 'X-Client-Cert-Start'
                    headerValue: '{var_client_certificate_start_date}'
                  }
                  {
                    headerName: 'X-Client-Cert-End'
                    headerValue: '{var_client_certificate_end_date}'
                  }
                  {
                    headerName: 'X-Client-Cert-Verify'
                    headerValue: '{var_client_certificate_verification}'
                  }
                ]
              }
            }
          ]
        }
      }
    ]
    requestRoutingRules: [
      {
        name: routingRuleName
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: '${appGwId}/httpListeners/${listenerName}'
          }
          backendAddressPool: {
            id: '${appGwId}/backendAddressPools/${backendPoolName}'
          }
          backendHttpSettings: {
            id: '${appGwId}/backendHttpSettingsCollection/${backendSettingsName}'
          }
          rewriteRuleSet: {
            id: '${appGwId}/rewriteRuleSets/${rewriteSetName}'
          }
        }
      }
    ]
    // WAF stays enabled via the associated policy (Prevention mode).
    // Only attach the WAF policy on the WAF_v2 SKU (Standard_v2 has no WAF).
    firewallPolicy: skuTier == 'WAF_v2' ? {
      id: wafPolicyId
    } : null
    forceFirewallPolicyAssociation: skuTier == 'WAF_v2'
  }
}

resource appGwDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'appgw-diagnostics'
  scope: appGateway
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'ApplicationGatewayAccessLog'
        enabled: true
      }
      {
        category: 'ApplicationGatewayFirewallLog'
        enabled: true
      }
      {
        category: 'ApplicationGatewayPerformanceLog'
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

output appGatewayName string = appGateway.name
output appGatewayId string = appGateway.id

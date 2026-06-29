// ========================================
// Application Gateway Module
// ========================================
// Deploys an Application Gateway (WAF_v2) that fronts the public API
// Management gateway, plus a comprehensive Azure Monitor diagnostic setting
// that streams every available log category and all metrics to Log Analytics.
//
// WAF_v2 is used deliberately so the ApplicationGatewayFirewallLog category is
// available - this lets the demo show the FULL App Gateway diagnostic surface.

@description('Location for the Application Gateway.')
param location string

@description('Name of the Application Gateway.')
param appGatewayName string

@description('Name of the Web Application Firewall policy.')
param wafPolicyName string

@description('Resource ID of the subnet dedicated to the Application Gateway.')
param subnetId string

@description('Resource ID of the public IP.')
param publicIpId string

@description('Backend host name (the APIM gateway FQDN, e.g. myapim.azure-api.net).')
param apimHostName string

@description('Log Analytics Workspace resource ID for diagnostic settings.')
param logAnalyticsWorkspaceId string

@description('Number of fixed Application Gateway instances.')
@minValue(1)
@maxValue(10)
param capacity int = 1

@description('Tags to apply to the resources.')
param tags object = {}

// ----------------------------------------
// Variables (child component names)
// ----------------------------------------

var gwIpConfigName = 'appGwIpConfig'
var frontendIpConfigName = 'appGwPublicFrontendIp'
var frontendPortName = 'port80'
var backendPoolName = 'apimBackendPool'
var backendHttpSettingsName = 'apimHttpsSettings'
var listenerName = 'httpListener'
var probeName = 'apimHealthProbe'
var routingRuleName = 'routeToApim'

// Pre-compute child resource IDs so the Application Gateway sub-resources can
// reference one another within the single resource definition.
var frontendIpConfigId = resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGatewayName, frontendIpConfigName)
var frontendPortId = resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, frontendPortName)
var backendPoolId = resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, backendPoolName)
var backendHttpSettingsId = resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, backendHttpSettingsName)
var listenerId = resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, listenerName)
var probeId = resourceId('Microsoft.Network/applicationGateways/probes', appGatewayName, probeName)

// ----------------------------------------
// Resources
// ----------------------------------------

// WAF policy in Detection mode so requests are evaluated and logged but not
// blocked - ideal for a demo that wants to surface firewall logs without
// breaking traffic. Uses the OWASP 3.2 managed rule set.
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-11-01' = {
  name: wafPolicyName
  location: location
  tags: tags
  properties: {
    policySettings: {
      state: 'Enabled'
      mode: 'Detection'
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
      ]
    }
  }
}

resource appGateway 'Microsoft.Network/applicationGateways@2023-11-01' = {
  name: appGatewayName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: capacity
    }
    gatewayIPConfigurations: [
      {
        name: gwIpConfigName
        properties: {
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: frontendIpConfigName
        properties: {
          publicIPAddress: {
            id: publicIpId
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: frontendPortName
        properties: {
          port: 80
        }
      }
    ]
    // Backend pool points at the public APIM gateway host name.
    backendAddressPools: [
      {
        name: backendPoolName
        properties: {
          backendAddresses: [
            {
              fqdn: apimHostName
            }
          ]
        }
      }
    ]
    // Custom health probe hits APIM's built-in health endpoint, which returns
    // HTTP 200 without a subscription key.
    probes: [
      {
        name: probeName
        properties: {
          protocol: 'Https'
          path: '/status-0123456789abcdef'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
    // HTTPS to APIM, with the Host header overridden to the APIM FQDN so APIM
    // routes the request correctly.
    backendHttpSettingsCollection: [
      {
        name: backendHttpSettingsName
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 30
          probe: {
            id: probeId
          }
        }
      }
    ]
    // Public HTTP listener on port 80 (no TLS certificate needed for the demo).
    httpListeners: [
      {
        name: listenerName
        properties: {
          frontendIPConfiguration: {
            id: frontendIpConfigId
          }
          frontendPort: {
            id: frontendPortId
          }
          protocol: 'Http'
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
            id: listenerId
          }
          backendAddressPool: {
            id: backendPoolId
          }
          backendHttpSettings: {
            id: backendHttpSettingsId
          }
        }
      }
    ]
    firewallPolicy: {
      id: wafPolicy.id
    }
  }
}

// =========================================================================
// Azure Monitor Diagnostic Settings for Application Gateway
// -------------------------------------------------------------------------
// Streams EVERY available App Gateway log category plus all metrics to
// Log Analytics. Available Application Gateway log categories:
//   - ApplicationGatewayAccessLog       : per-request access log (client IP,
//                                          URI, response code, latency, etc.)
//   - ApplicationGatewayPerformanceLog  : throughput / healthy-host metrics
//                                          (emitted by v1 SKUs)
//   - ApplicationGatewayFirewallLog      : WAF rule matches (requires a WAF SKU)
// AllMetrics captures throughput, request count, healthy host count, etc.
// =========================================================================
resource appGwDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'appgw-all-diagnostics'
  scope: appGateway
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'ApplicationGatewayAccessLog'
        enabled: true
      }
      {
        category: 'ApplicationGatewayPerformanceLog'
        enabled: true
      }
      {
        category: 'ApplicationGatewayFirewallLog'
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

// ----------------------------------------
// Outputs
// ----------------------------------------

@description('Resource ID of the Application Gateway.')
output appGatewayId string = appGateway.id

@description('Name of the Application Gateway.')
output appGatewayName string = appGateway.name

@description('Resource ID of the WAF policy.')
output wafPolicyId string = wafPolicy.id

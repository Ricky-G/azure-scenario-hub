@description('Azure region for Application Gateway and its WAF policy.')
param location string

@description('Name of the Application Gateway.')
param appGatewayName string

@description('Resource ID of the dedicated Application Gateway subnet.')
param appGatewaySubnetId string

@description('Resource ID of the dedicated Application Gateway Private Link subnet.')
param appGatewayPrivateLinkSubnetId string

@description('Resource ID of the platform-required public IP. No listener or routing rule uses this frontend.')
param appGatewayPublicIpId string

@description('Static private frontend IP address for Application Gateway.')
param appGatewayPrivateIp string = '10.10.1.10'

@description('Private IP address of the internal API Management service.')
param apimPrivateIp string

@description('API Management gateway hostname used for the backend host header and SNI.')
param apimGatewayHostname string

@description('Resource ID of the Log Analytics workspace.')
param logAnalyticsWorkspaceId string

@description('Tags applied to every resource.')
param tags object

var frontendIpName = 'private-frontend'
var publicFrontendIpName = 'public-frontend-no-listener'
var privateLinkConfigurationName = 'afd-private-link'
var gatewayIpConfigurationName = 'appgw-ipconfig'
var frontendPortName = 'http-80'
var listenerName = 'private-http-listener'
var backendPoolName = 'internal-apim'
var backendSettingsName = 'apim-https-settings'
var probeName = 'apim-status-probe'
var routingRuleName = 'apim-routing-rule'
var rewriteSetName = 'mark-private-appgw-hop'
var privateLinkConfigurationId = resourceId('Microsoft.Network/applicationGateways/privateLinkConfigurations', appGatewayName, privateLinkConfigurationName)
var frontendIpId = resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGatewayName, frontendIpName)
var frontendPortId = resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, frontendPortName)
var listenerId = resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, listenerName)
var backendPoolId = resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, backendPoolName)
var backendSettingsId = resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, backendSettingsName)
var probeId = resourceId('Microsoft.Network/applicationGateways/probes', appGatewayName, probeName)
var rewriteSetId = resourceId('Microsoft.Network/applicationGateways/rewriteRuleSets', appGatewayName, rewriteSetName)

resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2024-05-01' = {
  name: '${appGatewayName}-waf'
  location: location
  tags: tags
  properties: {
    policySettings: {
      state: 'Enabled'
      mode: 'Prevention'
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

resource appGateway 'Microsoft.Network/applicationGateways@2024-05-01' = {
  name: appGatewayName
  location: location
  tags: tags
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    autoscaleConfiguration: {
      minCapacity: 1
      maxCapacity: 2
    }
    enableHttp2: true
    gatewayIPConfigurations: [
      {
        name: gatewayIpConfigurationName
        properties: {
          subnet: {
            id: appGatewaySubnetId
          }
        }
      }
    ]
    privateLinkConfigurations: [
      {
        name: privateLinkConfigurationName
        id: privateLinkConfigurationId
        properties: {
          ipConfigurations: [
            {
              name: 'primary'
              properties: {
                primary: true
                privateIPAllocationMethod: 'Dynamic'
                subnet: {
                  id: appGatewayPrivateLinkSubnetId
                }
              }
            }
          ]
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: frontendIpName
        properties: {
          privateIPAddress: appGatewayPrivateIp
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: appGatewaySubnetId
          }
          privateLinkConfiguration: {
            id: privateLinkConfigurationId
          }
        }
      }
      {
        name: publicFrontendIpName
        properties: {
          publicIPAddress: {
            id: appGatewayPublicIpId
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
    httpListeners: [
      {
        name: listenerName
        properties: {
          frontendIPConfiguration: {
            id: frontendIpId
          }
          frontendPort: {
            id: frontendPortId
          }
          protocol: 'Http'
        }
      }
    ]
    backendAddressPools: [
      {
        name: backendPoolName
        properties: {
          backendAddresses: [
            {
              ipAddress: apimPrivateIp
            }
          ]
        }
      }
    ]
    probes: [
      {
        name: probeName
        properties: {
          protocol: 'Https'
          host: apimGatewayHostname
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
    backendHttpSettingsCollection: [
      {
        name: backendSettingsName
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          hostName: apimGatewayHostname
          pickHostNameFromBackendAddress: false
          requestTimeout: 60
          probe: {
            id: probeId
          }
        }
      }
    ]
    rewriteRuleSets: [
      {
        name: rewriteSetName
        properties: {
          rewriteRules: [
            {
              name: 'set-app-gateway-hop-header'
              ruleSequence: 100
              actionSet: {
                responseHeaderConfigurations: [
                  {
                    headerName: 'X-AppGateway-Hop'
                    headerValue: 'private-waf-v2'
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
            id: listenerId
          }
          backendAddressPool: {
            id: backendPoolId
          }
          backendHttpSettings: {
            id: backendSettingsId
          }
          rewriteRuleSet: {
            id: rewriteSetId
          }
        }
      }
    ]
    firewallPolicy: {
      id: wafPolicy.id
    }
    forceFirewallPolicyAssociation: true
  }
}

resource appGatewayDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
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

output appGatewayId string = appGateway.id
output appGatewayName string = appGateway.name
output appGatewayPrivateIp string = appGatewayPrivateIp
output frontendIpConfigurationName string = frontendIpName
output privateLinkConfigurationName string = privateLinkConfigurationName
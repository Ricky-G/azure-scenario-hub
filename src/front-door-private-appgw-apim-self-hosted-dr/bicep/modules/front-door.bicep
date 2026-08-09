@description('Name of the Azure Front Door Premium profile.')
param profileName string

@description('Name of the Azure Front Door endpoint.')
param endpointName string

@description('Resource ID of the private Application Gateway origin.')
param appGatewayId string

@description('Application Gateway frontend IP configuration name used as the Private Link group ID.')
param appGatewayFrontendIpConfigurationName string

@description('API Management gateway hostname sent as the happy-path origin host header.')
param apimGatewayHostname string

@description('Supported Azure Front Door Private Link region nearest to the origin.')
param privateLinkLocation string = 'australiaeast'

@description('Public FQDN of the AKS load balancer exposing the self-hosted gateway.')
param drOriginHostname string

@description('Resource ID of the Log Analytics workspace.')
param logAnalyticsWorkspaceId string

@description('Tags applied to Front Door resources that support tags.')
param tags object

resource profile 'Microsoft.Cdn/profiles@2024-09-01' = {
  name: profileName
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-09-01' = {
  name: endpointName
  parent: profile
  location: 'global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

resource happyOriginGroup 'Microsoft.Cdn/profiles/originGroups@2024-09-01' = {
  name: 'happy-private-origin-group'
  parent: profile
  properties: {
    healthProbeSettings: {
      probePath: '/status-0123456789abcdef'
      probeRequestType: 'GET'
      probeProtocol: 'Http'
      probeIntervalInSeconds: 60
    }
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    sessionAffinityState: 'Disabled'
  }
}

resource happyOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-09-01' = {
  name: 'private-application-gateway'
  parent: happyOriginGroup
  properties: {
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
    hostName: apimGatewayHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: apimGatewayHostname
    priority: 1
    weight: 1000
    sharedPrivateLinkResource: {
      groupId: appGatewayFrontendIpConfigurationName
      privateLink: {
        id: appGatewayId
      }
      privateLinkLocation: privateLinkLocation
      requestMessage: 'Azure Front Door private connectivity to the scenario Application Gateway.'
      status: 'Pending'
    }
  }
}

resource drOriginGroup 'Microsoft.Cdn/profiles/originGroups@2024-09-01' = {
  name: 'dr-public-origin-group'
  parent: profile
  properties: {
    healthProbeSettings: {
      probePath: '/status-0123456789abcdef'
      probeRequestType: 'GET'
      probeProtocol: 'Http'
      probeIntervalInSeconds: 60
    }
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    sessionAffinityState: 'Disabled'
  }
}

resource drOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-09-01' = {
  name: 'mock-onprem-self-hosted-gateway'
  parent: drOriginGroup
  properties: {
    enabledState: 'Enabled'
    enforceCertificateNameCheck: false
    hostName: drOriginHostname
    httpPort: 80
    httpsPort: 8081
    originHostHeader: drOriginHostname
    priority: 1
    weight: 1000
  }
}

resource happyRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-09-01' = {
  name: 'happy-route'
  parent: endpoint
  properties: {
    originGroup: {
      id: happyOriginGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/happy/*'
    ]
    forwardingProtocol: 'HttpOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
  dependsOn: [
    happyOrigin
  ]
}

resource drRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-09-01' = {
  name: 'dr-route'
  parent: endpoint
  properties: {
    originGroup: {
      id: drOriginGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/dr/*'
    ]
    forwardingProtocol: 'HttpOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
  dependsOn: [
    drOrigin
  ]
}

resource wafPolicy 'Microsoft.Network/frontdoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: toLower('${replace(profileName, '-', '')}waf')
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: 'Prevention'
      requestBodyCheck: 'Enabled'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.1'
          ruleSetAction: 'Block'
        }
      ]
    }
  }
}

resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2024-09-01' = {
  name: 'default-waf-security-policy'
  parent: profile
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: endpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
  dependsOn: [
    happyRoute
    drRoute
  ]
}

resource frontDoorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'frontdoor-diagnostics'
  scope: profile
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'FrontDoorAccessLog'
        enabled: true
      }
      {
        category: 'FrontDoorHealthProbeLog'
        enabled: true
      }
      {
        category: 'FrontDoorWebApplicationFirewallLog'
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

output profileId string = profile.id
output profileName string = profile.name
output endpointName string = endpoint.name
output endpointHostname string = endpoint.properties.hostName
output endpointUrl string = 'https://${endpoint.properties.hostName}'
output happyUrl string = 'https://${endpoint.properties.hostName}/happy/hello'
output drUrl string = 'https://${endpoint.properties.hostName}/dr/hello'
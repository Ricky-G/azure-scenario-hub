// =====================================================================
// WAF Policy module (OWASP, Prevention mode)
// =====================================================================
// The hard constraint for this POC is that the Azure WAF is RETAINED.
// This policy keeps WAF_v2 in Prevention mode with the OWASP managed
// rule set, but EXCLUDES the forwarded client-certificate headers from
// inspection. The forwarded PEM is a large base64 blob and would
// otherwise risk false-positive matches in the managed rules.
// =====================================================================

@description('Azure region for the WAF policy.')
param location string

@description('Name of the WAF policy.')
param wafPolicyName string

@description('Tags applied to the WAF policy.')
param tags object

resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-11-01' = {
  name: wafPolicyName
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
      // Exclude the App Gateway -> APIM certificate-forwarding headers from
      // WAF inspection so the base64 PEM payload cannot trip managed rules.
      exclusions: [
        {
          matchVariable: 'RequestHeaderNames'
          selectorMatchOperator: 'StartsWith'
          selector: 'X-Client-Cert'
        }
      ]
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
      ]
    }
  }
}

output wafPolicyId string = wafPolicy.id
output wafPolicyName string = wafPolicy.name

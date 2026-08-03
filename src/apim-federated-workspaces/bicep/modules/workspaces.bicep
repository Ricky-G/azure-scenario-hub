@description('Name of the existing API Management service.')
param apimServiceName string

@description('Resource ID of the Log Analytics workspace used for federated gateway logs.')
param logAnalyticsWorkspaceId string

@description('Whether to install the demo service-level global policy. Enable only on a disposable APIM service because this replaces the existing global policy.')
param configureGlobalPolicy bool = false

@description('Optional object ID of the Microsoft Entra group or user representing the Data Science team.')
param dataScienceTeamPrincipalId string = ''

@description('Optional object ID of the Microsoft Entra group or user representing the Website Experience team.')
param websiteTeamPrincipalId string = ''

@description('Microsoft Entra principal type used for optional workspace role assignments.')
@allowed([
  'Group'
  'User'
  'ServicePrincipal'
])
param teamPrincipalType string = 'Group'

var serviceWorkspaceDeveloperRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9565a273-41b9-4368-97d2-aeb0c976a9b3')
var workspaceContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0c34c906-8d99-4cb7-8bb7-33f5b0a1a799')

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

resource globalPolicy 'Microsoft.ApiManagement/service/policies@2024-05-01' = if (configureGlobalPolicy) {
  parent: apimService
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
      <policies>
        <inbound>
          <set-variable name="platform-governance" value="central-platform-baseline-v1" />
        </inbound>
        <backend><forward-request /></backend>
        <outbound />
        <on-error />
      </policies>
    '''
  }
}

resource serviceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'apim-federated-platform-logs'
  scope: apimService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
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

resource dataScienceWorkspace 'Microsoft.ApiManagement/service/workspaces@2024-05-01' = {
  parent: apimService
  name: 'data-science'
  properties: {
    displayName: 'Data Science Team'
    description: 'Team-owned machine learning inference APIs, products, policies, and subscriptions.'
  }
}

resource websiteWorkspace 'Microsoft.ApiManagement/service/workspaces@2024-05-01' = {
  parent: apimService
  name: 'website-experience'
  properties: {
    displayName: 'Website Experience Team'
    description: 'Team-owned digital experience APIs, products, policies, and subscriptions.'
  }
}

resource dataScienceWorkspacePolicy 'Microsoft.ApiManagement/service/workspaces/policies@2024-05-01' = {
  parent: dataScienceWorkspace
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
      <policies>
        <inbound>
          <base />
          <set-variable name="workspace-owner" value="{{ds-team-name}}" />
        </inbound>
        <backend>
          <base />
        </backend>
        <outbound>
          <base />
        </outbound>
        <on-error>
          <base />
        </on-error>
      </policies>
    '''
  }
  dependsOn: [
    dataScienceTeamName
  ]
}

resource websiteWorkspacePolicy 'Microsoft.ApiManagement/service/workspaces/policies@2024-05-01' = {
  parent: websiteWorkspace
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
      <policies>
        <inbound>
          <base />
          <set-variable name="workspace-owner" value="{{web-team-name}}" />
        </inbound>
        <backend>
          <base />
        </backend>
        <outbound>
          <base />
        </outbound>
        <on-error>
          <base />
        </on-error>
      </policies>
    '''
  }
  dependsOn: [
    websiteTeamName
  ]
}

resource dataScienceTeamName 'Microsoft.ApiManagement/service/workspaces/namedValues@2024-05-01' = {
  parent: dataScienceWorkspace
  name: 'ds-team-name'
  properties: {
    displayName: 'ds-team-name'
    value: 'Data Science Team'
    secret: false
  }
}

resource websiteTeamName 'Microsoft.ApiManagement/service/workspaces/namedValues@2024-05-01' = {
  parent: websiteWorkspace
  name: 'web-team-name'
  properties: {
    displayName: 'web-team-name'
    value: 'Website Experience Team'
    secret: false
  }
}

resource dataScienceStandards 'Microsoft.ApiManagement/service/workspaces/policyFragments@2024-05-01' = {
  parent: dataScienceWorkspace
  name: 'ds-team-standards'
  properties: {
    description: 'Reusable Data Science team policy baseline.'
    format: 'rawxml'
    value: '<fragment><set-variable name="team-policy-version" value="ds-standards-v1" /></fragment>'
  }
}

resource websiteStandards 'Microsoft.ApiManagement/service/workspaces/policyFragments@2024-05-01' = {
  parent: websiteWorkspace
  name: 'web-team-standards'
  properties: {
    description: 'Reusable Website Experience team policy baseline.'
    format: 'rawxml'
    value: '<fragment><set-variable name="team-policy-version" value="web-standards-v1" /></fragment>'
  }
}

resource dataScienceApi 'Microsoft.ApiManagement/service/workspaces/apis@2024-05-01' = {
  parent: dataScienceWorkspace
  name: 'ds-fraud-risk-api'
  properties: {
    displayName: 'Fraud Risk Inference API'
    description: 'Policy-only demonstration of a team-managed model inference API.'
    path: 'ai-insights'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    type: 'http'
  }
}

resource scoreOperation 'Microsoft.ApiManagement/service/workspaces/apis/operations@2024-05-01' = {
  parent: dataScienceApi
  name: 'score-risk'
  properties: {
    displayName: 'Score fraud risk'
    method: 'GET'
    urlTemplate: '/score'
    description: 'Returns a deterministic sample inference result for the demo.'
    templateParameters: []
    responses: [
      {
        statusCode: 200
        description: 'Inference result'
      }
      {
        statusCode: 429
        description: 'Data Science team rate limit exceeded'
      }
    ]
  }
}

resource scoreOperationPolicy 'Microsoft.ApiManagement/service/workspaces/apis/operations/policies@2024-05-01' = {
  parent: scoreOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
      <policies>
        <inbound>
          <base />
          <include-fragment fragment-id="ds-team-standards" />
          <rate-limit-by-key calls="5" renewal-period="60" counter-key="@(context.Request.Headers.GetValueOrDefault(&quot;X-Demo-Client&quot;, context.Request.IpAddress))" />
          <return-response>
            <set-status code="200" reason="OK" />
            <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
            <set-header name="X-Platform-Governance" exists-action="override"><value>@(context.Variables.GetValueOrDefault&lt;string&gt;("platform-governance", "customer-managed-global-policy"))</value></set-header>
            <set-header name="X-Workspace-Owner" exists-action="override"><value>@(context.Variables.GetValueOrDefault&lt;string&gt;("workspace-owner", "missing"))</value></set-header>
            <set-header name="X-Team-Policy" exists-action="override"><value>@(context.Variables.GetValueOrDefault&lt;string&gt;("team-policy-version", "missing"))</value></set-header>
            <set-body>{"model":"fraud-risk-v3","prediction":"low-risk","confidence":0.97,"servedBy":"data-science"}</set-body>
          </return-response>
        </inbound>
        <backend><base /></backend>
        <outbound><base /></outbound>
        <on-error><base /></on-error>
      </policies>
    '''
  }
  dependsOn: [
    dataScienceStandards
    dataScienceWorkspacePolicy
  ]
}

resource websiteApi 'Microsoft.ApiManagement/service/workspaces/apis@2024-05-01' = {
  parent: websiteWorkspace
  name: 'web-personalization-api'
  properties: {
    displayName: 'Website Personalization API'
    description: 'Policy-only demonstration of a team-managed digital experience API.'
    path: 'digital-experience'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    type: 'http'
  }
}

resource experienceOperation 'Microsoft.ApiManagement/service/workspaces/apis/operations@2024-05-01' = {
  parent: websiteApi
  name: 'get-homepage-experience'
  properties: {
    displayName: 'Get homepage experience'
    method: 'GET'
    urlTemplate: '/homepage'
    description: 'Returns a deterministic personalized web experience for the demo.'
    templateParameters: []
    responses: [
      {
        statusCode: 200
        description: 'Personalized experience'
      }
      {
        statusCode: 429
        description: 'Website Experience team rate limit exceeded'
      }
    ]
  }
}

resource experienceOperationPolicy 'Microsoft.ApiManagement/service/workspaces/apis/operations/policies@2024-05-01' = {
  parent: experienceOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
      <policies>
        <inbound>
          <base />
          <include-fragment fragment-id="web-team-standards" />
          <rate-limit-by-key calls="20" renewal-period="60" counter-key="@(context.Request.Headers.GetValueOrDefault(&quot;X-Demo-Client&quot;, context.Request.IpAddress))" />
          <return-response>
            <set-status code="200" reason="OK" />
            <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
            <set-header name="X-Platform-Governance" exists-action="override"><value>@(context.Variables.GetValueOrDefault&lt;string&gt;("platform-governance", "customer-managed-global-policy"))</value></set-header>
            <set-header name="X-Workspace-Owner" exists-action="override"><value>@(context.Variables.GetValueOrDefault&lt;string&gt;("workspace-owner", "missing"))</value></set-header>
            <set-header name="X-Team-Policy" exists-action="override"><value>@(context.Variables.GetValueOrDefault&lt;string&gt;("team-policy-version", "missing"))</value></set-header>
            <set-body>{"experience":"homepage","campaign":"summer-launch","variant":"B","servedBy":"website-experience"}</set-body>
          </return-response>
        </inbound>
        <backend><base /></backend>
        <outbound><base /></outbound>
        <on-error><base /></on-error>
      </policies>
    '''
  }
  dependsOn: [
    websiteStandards
    websiteWorkspacePolicy
  ]
}

resource dataScienceProduct 'Microsoft.ApiManagement/service/workspaces/products@2024-05-01' = {
  parent: dataScienceWorkspace
  name: 'ds-model-products'
  properties: {
    displayName: 'Data Science Model APIs'
    description: 'Published APIs owned and productized by the Data Science team.'
    state: 'published'
    subscriptionRequired: false
  }
}

resource dataScienceProductApi 'Microsoft.ApiManagement/service/workspaces/products/apiLinks@2024-05-01' = {
  parent: dataScienceProduct
  name: 'ds-product-api-link'
  properties: {
    apiId: dataScienceApi.id
  }
}

resource websiteProduct 'Microsoft.ApiManagement/service/workspaces/products@2024-05-01' = {
  parent: websiteWorkspace
  name: 'web-experience-products'
  properties: {
    displayName: 'Digital Experience APIs'
    description: 'Published APIs owned and productized by the Website Experience team.'
    state: 'published'
    subscriptionRequired: false
  }
}

resource websiteProductApi 'Microsoft.ApiManagement/service/workspaces/products/apiLinks@2024-05-01' = {
  parent: websiteProduct
  name: 'web-product-api-link'
  properties: {
    apiId: websiteApi.id
  }
}

resource dataScienceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'data-science-gateway-logs'
  scope: dataScienceWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
      }
    ]
  }
}

resource websiteDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'website-experience-gateway-logs'
  scope: websiteWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
      }
    ]
  }
}

resource dataScienceServiceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(dataScienceTeamPrincipalId)) {
  name: guid(apimService.id, dataScienceTeamPrincipalId, serviceWorkspaceDeveloperRoleId)
  scope: apimService
  properties: {
    principalId: dataScienceTeamPrincipalId
    principalType: teamPrincipalType
    roleDefinitionId: serviceWorkspaceDeveloperRoleId
  }
}

resource dataScienceWorkspaceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(dataScienceTeamPrincipalId)) {
  name: guid(dataScienceWorkspace.id, dataScienceTeamPrincipalId, workspaceContributorRoleId)
  scope: dataScienceWorkspace
  properties: {
    principalId: dataScienceTeamPrincipalId
    principalType: teamPrincipalType
    roleDefinitionId: workspaceContributorRoleId
  }
}

resource websiteServiceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(websiteTeamPrincipalId)) {
  name: guid(apimService.id, websiteTeamPrincipalId, serviceWorkspaceDeveloperRoleId)
  scope: apimService
  properties: {
    principalId: websiteTeamPrincipalId
    principalType: teamPrincipalType
    roleDefinitionId: serviceWorkspaceDeveloperRoleId
  }
}

resource websiteWorkspaceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(websiteTeamPrincipalId)) {
  name: guid(websiteWorkspace.id, websiteTeamPrincipalId, workspaceContributorRoleId)
  scope: websiteWorkspace
  properties: {
    principalId: websiteTeamPrincipalId
    principalType: teamPrincipalType
    roleDefinitionId: workspaceContributorRoleId
  }
}

@description('Resource ID of the Data Science workspace.')
output dataScienceWorkspaceId string = dataScienceWorkspace.id

@description('Resource ID of the Website Experience workspace.')
output websiteWorkspaceId string = websiteWorkspace.id

@description('Names of the APIs deployed to each workspace.')
output apiNames object = {
  dataScience: dataScienceApi.name
  website: websiteApi.name
}

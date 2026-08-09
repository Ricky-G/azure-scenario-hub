@description('Azure region for the AKS cluster and public IP address.')
param location string

@description('Short prefix applied to resource names.')
param namePrefix string

@description('Deterministic suffix for globally unique names.')
param suffix string

@description('Resource ID of the subnet used by AKS nodes.')
param aksSubnetId string

@description('Name of the virtual network containing the AKS subnet.')
param mockOnPremVnetName string

@description('Name of the subnet used by AKS nodes.')
param aksSubnetName string

@description('Resource ID of the Log Analytics workspace.')
param logAnalyticsWorkspaceId string

@description('Kubernetes minor version supported in the deployment region.')
param kubernetesVersion string = '1.34'

@description('Virtual machine size for the single POC system node.')
param nodeVmSize string = 'Standard_D2s_v5'

@description('Tags applied to every resource.')
param tags object

var clusterName = '${namePrefix}-aks'
var identityName = '${namePrefix}-aks-id'
var drPublicIpName = '${namePrefix}-dr-pip'
var networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7'

resource mockOnPremVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: mockOnPremVnetName
}

resource aksSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: aksSubnetName
  parent: mockOnPremVnet
}

resource controlPlaneIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

resource drPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: drPublicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: toLower('${namePrefix}dr${suffix}')
    }
  }
}

resource subnetNetworkContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksSubnet.id, controlPlaneIdentity.id, networkContributorRoleId)
  scope: aksSubnet
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
    principalId: controlPlaneIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource publicIpNetworkContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(drPublicIp.id, controlPlaneIdentity.id, networkContributorRoleId)
  scope: drPublicIp
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
    principalId: controlPlaneIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource cluster 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: clusterName
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${controlPlaneIdentity.id}': {}
    }
  }
  properties: {
    dnsPrefix: toLower('${namePrefix}-aks-${suffix}')
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    disableLocalAccounts: false
    nodeResourceGroup: '${namePrefix}-aks-nodes'
    agentPoolProfiles: [
      {
        name: 'system'
        count: 1
        vmSize: nodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: aksSubnetId
        osDiskType: 'Managed'
        osDiskSizeGB: 64
        enableAutoScaling: false
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'azure'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
      serviceCidr: '10.30.0.0/16'
      dnsServiceIP: '10.30.0.10'
      podCidr: '10.40.0.0/16'
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
          useAADAuth: 'true'
        }
      }
      azurepolicy: {
        enabled: false
      }
    }
  }
  dependsOn: [
    subnetNetworkContributor
    publicIpNetworkContributor
  ]
}

output clusterId string = cluster.id
output clusterName string = cluster.name
output drPublicIpId string = drPublicIp.id
output drPublicIpName string = drPublicIp.name
output drPublicIpAddress string = drPublicIp.properties.ipAddress
output drPublicIpFqdn string = drPublicIp.properties.dnsSettings.fqdn
output controlPlaneIdentityPrincipalId string = controlPlaneIdentity.properties.principalId
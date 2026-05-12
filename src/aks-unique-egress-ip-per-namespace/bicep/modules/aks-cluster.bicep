@description('Azure region for all resources.')
param location string

@description('Short prefix applied to all resource names.')
param namePrefix string

@description('Kubernetes version for the AKS cluster.')
param kubernetesVersion string

@description('Number of nodes in the system node pool.')
param systemNodeCount int

@description('VM size for system node pool nodes.')
param systemNodeVmSize string

@description('Tags to apply to all resources.')
param tags object

@description('Name of the ACR to attach for image pull.')
param acrName string

// Derive cluster name deterministically
var clusterName = '${namePrefix}-aks-${uniqueString(resourceGroup().id)}'
var nodeResourceGroupName = 'MC_${resourceGroup().name}_${clusterName}_${location}'

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: '${namePrefix}-${uniqueString(resourceGroup().id)}'
    kubernetesVersion: kubernetesVersion
    nodeResourceGroup: nodeResourceGroupName
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      podCidr: '192.168.0.0/16'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
    }
    agentPoolProfiles: [
      {
        name: 'system'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        mode: 'System'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        type: 'VirtualMachineScaleSets'
        enableAutoScaling: false
      }
    ]
    // Note: Static Egress Gateway is enabled via az aks update --enable-static-egress-gateway
    // (requires aks-preview CLI extension) as the ARM API does not accept this field directly.
  }
}

// Grant AcrPull role to the kubelet identity
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// AcrPull role definition ID
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, acr.id, acrPullRoleId)
  scope: acr
  properties: {
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalType: 'ServicePrincipal'
  }
}

@description('The name of the AKS cluster.')
output clusterName string = aksCluster.name

@description('The FQDN of the AKS cluster.')
output clusterFqdn string = aksCluster.properties.fqdn

@description('The kubelet identity object ID.')
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId

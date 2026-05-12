// AKS Static Egress Gateway — Unique Egress IP per Namespace
// Deploys AKS cluster with Static Egress Gateway, ACR, and gateway node pool support

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Short prefix applied to all resource names for uniqueness.')
@minLength(3)
@maxLength(12)
param namePrefix string = 'egressdemo'

@description('Kubernetes version for the AKS cluster.')
param kubernetesVersion string = '1.34'

@description('Number of nodes in the system node pool.')
@minValue(1)
@maxValue(5)
param systemNodeCount int = 2

@description('VM size for system node pool nodes.')
param systemNodeVmSize string = 'Standard_D2s_v5'

// Variables
var commonTags = {
  Environment: 'Demo'
  Project: 'AzureScenarioHub'
  Scenario: 'AKS-Static-Egress-Gateway'
  ManagedBy: 'Bicep'
}

// Deploy ACR first (needed for AKS AcrPull role)
module acr 'modules/acr.bicep' = {
  name: 'acrDeploy'
  params: {
    location: location
    namePrefix: namePrefix
    tags: commonTags
  }
}

// Deploy AKS cluster with Static Egress Gateway enabled
module aksCluster 'modules/aks-cluster.bicep' = {
  name: 'aksDeploy'
  params: {
    location: location
    namePrefix: namePrefix
    kubernetesVersion: kubernetesVersion
    systemNodeCount: systemNodeCount
    systemNodeVmSize: systemNodeVmSize
    acrName: acr.outputs.acrName
    tags: commonTags
  }
}

// Outputs
@description('The name of the AKS cluster.')
output clusterName string = aksCluster.outputs.clusterName

@description('The FQDN of the AKS cluster.')
output clusterFqdn string = aksCluster.outputs.clusterFqdn

@description('The name of the ACR.')
output acrName string = acr.outputs.acrName

@description('The login server of the ACR.')
output acrLoginServer string = acr.outputs.acrLoginServer

@description('The resource group name.')
output resourceGroupName string = resourceGroup().name

@description('Command to get AKS credentials.')
output getCredentialsCommand string = 'az aks get-credentials --resource-group ${resourceGroup().name} --name ${aksCluster.outputs.clusterName}'

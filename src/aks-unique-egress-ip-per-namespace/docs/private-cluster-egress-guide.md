# Private Cluster Egress Guide — Static Egress Gateway with Private IPs

This guide explains how to use AKS Static Egress Gateway with **private IPs** instead of public IPs, suitable for private AKS clusters that egress to on-premises networks, peered VNets, or private services.

## Overview

In the [main demo](../README.md), each namespace gets a **public IP prefix** for egress. But in enterprise environments with private AKS clusters, you typically need:

- Egress to on-prem services via ExpressRoute/VPN
- Egress to peered VNets
- No public IP exposure at all
- Downstream firewalls/NVAs that allowlist by private IP

Static Egress Gateway supports this via `provisionPublicIps: false`.

## Architecture — Private Egress

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Azure VNet: 10.224.0.0/16                                                 │
│                                                                             │
│  ┌─── AKS Cluster (Private, Azure CNI Overlay) ──────────────────────────┐ │
│  │                                                                        │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐     │ │
│  │  │ namespace-team-a │  │ namespace-team-b │  │ namespace-team-c │     │ │
│  │  │  app workloads   │  │  app workloads   │  │  app workloads   │     │ │
│  │  │ egress: 10.224.  │  │ egress: 10.224.  │  │ egress: 10.224.  │     │ │
│  │  │        0.20      │  │        0.21      │  │        0.22      │     │ │
│  │  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘    │ │
│  │           └──────────────────────┼──────────────────────┘              │ │
│  │                                  ▼                                     │ │
│  │                    ┌──────────────────────┐                            │ │
│  │                    │  Gateway Node Pool   │                            │ │
│  │                    │  2 nodes (HA)        │                            │ │
│  │                    │  Node 1: 10.224.0.6  │                            │ │
│  │                    │  Node 2: 10.224.0.15 │                            │ │
│  │                    └──────────┬───────────┘                            │ │
│  └───────────────────────────────┼────────────────────────────────────────┘ │
│                                  │                                          │
│                                  ▼                                          │
│  ┌───────────────────────────────────────────────────────────────────┐      │
│  │  On-Prem / Peered VNet / NVA Firewall                            │      │
│  │  Allowlist rules:                                                 │      │
│  │    team-a traffic → expect from 10.224.0.20                       │      │
│  │    team-b traffic → expect from 10.224.0.21                       │      │
│  │    team-c traffic → expect from 10.224.0.22                       │      │
│  └───────────────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Differences from Public Mode

| Aspect | Public Mode (main demo) | Private Mode |
|---|---|---|
| `provisionPublicIps` | `true` (default) | `false` |
| Egress IPs come from | Auto-created Azure Public IP Prefix | Gateway node private IPs on VNet subnet |
| Azure resources created | 1 Public IP Prefix per namespace config | None (uses existing subnet IPs) |
| Minimum K8s version | Any supported | **1.34+** |
| Gateway VM set type | Any | Must be `VirtualMachines` |
| Subnet planning | No change needed | Ensure subnet has enough IPs |
| Use case | Internet egress | On-prem, peered VNets, private services |

## Step-by-Step Setup

### Prerequisites

- AKS cluster with **Kubernetes 1.34+**
- **Azure CNI Overlay** network plugin
- **aks-preview** CLI extension installed
- Static Egress Gateway feature registered

### 1. Create AKS Cluster (Private)

```bash
# Register feature
az feature register --namespace Microsoft.ContainerService --name StaticEgressGatewayPreview
az provider register --namespace Microsoft.ContainerService

# Create private AKS cluster with Azure CNI Overlay
az aks create \
  --name my-private-aks \
  --resource-group rg-private-egress \
  --location westus3 \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --pod-cidr 192.168.0.0/16 \
  --enable-private-cluster \
  --kubernetes-version 1.34 \
  --node-count 2

# Enable Static Egress Gateway
az aks update -n my-private-aks -g rg-private-egress --enable-static-egress-gateway
```

### 2. Add Gateway Node Pool (Private Mode)

The key difference: `--vm-set-type VirtualMachines` is required for private IP support.

```bash
az aks nodepool add \
  --cluster-name my-private-aks \
  --name gateway \
  --resource-group rg-private-egress \
  --mode gateway \
  --node-count 2 \
  --vm-set-type VirtualMachines \
  --gateway-prefix-size 28 \
  --vm-size Standard_D2s_v5
```

### 3. Create StaticGatewayConfiguration with Private IPs

The critical field: `provisionPublicIps: false`

```yaml
# gateway-config-private.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: team-a
---
apiVersion: egressgateway.kubernetes.azure.com/v1alpha1
kind: StaticGatewayConfiguration
metadata:
  name: egress-config
  namespace: team-a
spec:
  gatewayNodepoolName: gateway
  provisionPublicIps: false          # ← Private IPs only
  excludeCidrs:
    - 10.0.0.0/8                     # Exclude cluster-internal traffic
    - 172.16.0.0/12
    - 169.254.169.254/32             # Azure IMDS
---
apiVersion: v1
kind: Namespace
metadata:
  name: team-b
---
apiVersion: egressgateway.kubernetes.azure.com/v1alpha1
kind: StaticGatewayConfiguration
metadata:
  name: egress-config
  namespace: team-b
spec:
  gatewayNodepoolName: gateway
  provisionPublicIps: false
  excludeCidrs:
    - 10.0.0.0/8
    - 172.16.0.0/12
    - 169.254.169.254/32
```

### 4. Apply and Verify

```bash
kubectl apply -f gateway-config-private.yaml

# Wait ~60s for IPs to provision, then check assigned private IPs
kubectl describe staticgatewayconfiguration egress-config -n team-a
```

The `egressIpPrefix` in the status will show **private IPs** from the node subnet:

```
Status:
  Egress Ip Prefix:  10.224.0.20,10.224.0.21
```

### 5. Annotate Workloads

Same as public mode — the only difference is in the `StaticGatewayConfiguration`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: team-a
spec:
  template:
    metadata:
      annotations:
        kubernetes.azure.com/static-gateway-configuration: egress-config
    spec:
      containers:
        - name: my-app
          image: my-app:latest
```

## Subnet Sizing

For private mode, the gateway controller allocates secondary private IPs from the gateway nodes' subnet. Plan your subnet to accommodate:

| Component | IPs needed |
|---|---|
| Gateway nodes | 2 (for HA) |
| Per-namespace egress IPs | 1+ per StaticGatewayConfiguration |
| System overhead | ~5 (Azure reserved) |

**Example**: 10 namespaces + 2 gateway nodes + 5 reserved = 17 IPs → a `/27` (32 IPs) is sufficient. A `/24` (256 IPs) gives comfortable headroom.

## Comparison: Old Approach vs Static Egress Gateway

If you're migrating from the legacy pattern of "one subnet + one NAT Gateway per namespace":

| | Old approach | Static Egress Gateway (Private) |
|---|---|---|
| Subnets needed | **One per namespace** | **One total** |
| Node pools needed | **One per namespace** | **One gateway pool** |
| NAT Gateways | **One per namespace** | **None** |
| IP control | Manual per subnet/NAT | Automatic from single subnet |
| Cost | High (extra VMs + NAT GWs) | Low (2 small gateway nodes) |

## OpenShift EgressIP Comparison

For teams migrating from OpenShift:

| Feature | OpenShift EgressIP | AKS Static Egress Gateway (Private) |
|---|---|---|
| Per-namespace static IP | `EgressIP` CR on namespace | `StaticGatewayConfiguration` + pod annotation |
| Private IPs | Yes (node IPs) | Yes (`provisionPublicIps: false`) |
| Public IPs | Limited | Yes (`provisionPublicIps: true`) |
| Dedicated nodes | No (uses worker nodes) | Yes (gateway node pool) |
| HA / failover | Automatic reassignment | Gateway pool (2+ nodes) |

## References

- [AKS Static Egress Gateway — Private IP Support](https://learn.microsoft.com/en-us/azure/aks/configure-static-egress-gateway#static-private-ip-support)
- [AKS Private Clusters](https://learn.microsoft.com/en-us/azure/aks/private-clusters)
- [Azure CNI Overlay](https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay)

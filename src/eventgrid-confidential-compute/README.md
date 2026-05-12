# Event Grid System Topic with Confidential Compute

This scenario demonstrates how to deploy an Azure Event Grid System Topic with **Azure Confidential Compute** enabled. This feature ensures that messages are processed and stored in a Confidential Compute environment, providing enhanced security for sensitive workloads.

## Overview

Azure Confidential Compute for Event Grid System Topics is a platform capability that encrypts and processes events in a secure enclave environment. This is particularly useful for scenarios requiring:

- Enhanced data protection during event processing
- Compliance with strict security requirements
- Processing sensitive or regulated data through Event Grid

> **Important**: 
> - The `confidentialCompute.mode` property is **immutable** - it can only be set at resource creation time and cannot be modified later.
> - **This is a preview feature** with limited regional availability. As of February 2026, Confidential Compute for Event Grid is **only available in Korea Central and UAE North regions**.

## Architecture

```
┌─────────────────────┐         ┌──────────────────────────────────┐
│   Storage Account   │────────▶│  Event Grid System Topic         │
│   (Event Source)    │         │  (Confidential Compute Enabled)  │
└─────────────────────┘         └──────────────────────────────────┘
```

## Resources Deployed

| Resource | Description |
|----------|-------------|
| Resource Group | `rg-event-grid-confidential-compute` |
| Storage Account | Source for blob events |
| Event Grid System Topic | System topic with Confidential Compute enabled |

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with appropriate permissions
- Bicep CLI installed (comes with Azure CLI)

## Supported Regions

**Confidential Compute for Event Grid System Topics is currently only available in:**
- **Korea Central** (`koreacentral`)
- **UAE North** (`uaenorth`)

For deployments to other regions, set `enableConfidentialCompute=false` to deploy a standard Event Grid System Topic.

## Deployment

### Option 1: Using Azure CLI

```powershell
# Login to Azure
az login

# Deploy with Confidential Compute enabled (Korea Central or UAE North only)
az deployment sub create `
    --name "eventgrid-confidential-compute-deployment" `
    --location "koreacentral" `
    --template-file ./bicep/main.bicep `
    --parameters location=koreacentral enableConfidentialCompute=true
```

### Option 2: Using the deploy script

```powershell
# Run the deployment script
./bicep/deploy.ps1
```

## Parameters

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| `location` | `westus` | Azure region for deployment |
| `resourceGroupName` | `rg-event-grid-confidential-compute` | Name of the resource group |
| `namePrefix` | `egcc` | Prefix for resource names |
| `enableConfidentialCompute` | `false` | Enable Confidential Compute (only supported in Korea Central and UAE North) |

## Enabling Confidential Compute

To deploy with Confidential Compute enabled in a supported region:

```powershell
# Deploy to Korea Central with Confidential Compute
az deployment sub create `
    --name "eventgrid-confidential-compute-deployment" `
    --location "koreacentral" `
    --template-file ./bicep/main.bicep `
    --parameters location=koreacentral enableConfidentialCompute=true

# Or deploy to UAE North with Confidential Compute
az deployment sub create `
    --name "eventgrid-confidential-compute-deployment" `
    --location "uaenorth" `
    --template-file ./bicep/main.bicep `
    --parameters location=uaenorth enableConfidentialCompute=true
```

> **Note**: If deploying to other regions, set `enableConfidentialCompute=false` or omit the parameter to deploy a standard Event Grid System Topic.

## Confidential Compute Configuration

The key configuration for enabling Confidential Compute in the System Topic is:

```bicep
resource systemTopic 'Microsoft.EventGrid/systemTopics@2025-07-15-preview' = {
  name: systemTopicName
  location: location
  properties: {
    source: sourceResourceId
    topicType: 'Microsoft.Storage.StorageAccounts'
    platformCapabilities: {
      confidentialCompute: {
        mode: 'Enabled'  // or 'Disabled'
      }
    }
  }
}
```

### Mode Values

| Mode | Description |
|------|-------------|
| `Enabled` | Events are processed in Azure Confidential Compute environment |
| `Disabled` | Standard event processing (default behavior) |

## API Version

This scenario uses API version `2025-07-15-preview` which introduced the `platformCapabilities.confidentialCompute` feature for System Topics.

## Testing

After deployment, you can test the System Topic by:

1. Upload a blob to the storage account's `test-container`
2. Check the Event Grid System Topic metrics in the Azure Portal
3. Create an event subscription to receive events

## Cleanup

To remove all resources:

```powershell
az group delete --name rg-event-grid-confidential-compute --yes --no-wait
```

## References

- [Event Grid System Topics - Bicep Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.eventgrid/2025-07-15-preview/systemtopics?pivots=deployment-language-bicep)
- [Azure Confidential Computing](https://learn.microsoft.com/en-us/azure/confidential-computing/overview)
- [Event Grid Overview](https://learn.microsoft.com/en-us/azure/event-grid/overview)

## Tags

- Event Grid
- Confidential Compute
- Security
- System Topics
- Bicep

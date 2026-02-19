#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Deploy Azure API Management Monitoring Scenario

.DESCRIPTION
    This script deploys the APIM monitoring scenario including:
    - Resource Group
    - API Management Developer SKU
    - 6 Sample APIs with policies

.PARAMETER Location
    Azure region for deployment (default: eastus)

.PARAMETER ApimServiceName
    Name for the API Management service (must be globally unique)

.PARAMETER PublisherEmail
    Email address for the API publisher (default: admin@example.com)

.PARAMETER PublisherName
    Organization name for the API publisher (default: Contoso)

.PARAMETER EnableAppInsights
    Enable Application Insights integration (default: false)

.PARAMETER SkipConfirmation
    Skip deployment confirmation prompt

.EXAMPLE
    .\deploy.ps1 -Location "eastus" -ApimServiceName "apim-demo-unique123"

.EXAMPLE
    .\deploy.ps1 -ApimServiceName "my-apim-001" -EnableAppInsights -SkipConfirmation
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",

    [Parameter(Mandatory = $true)]
    [ValidateLength(1, 50)]
    [string]$ApimServiceName,

    [Parameter(Mandatory = $false)]
    [string]$PublisherEmail = "admin@example.com",

    [Parameter(Mandatory = $false)]
    [string]$PublisherName = "Contoso",

    [Parameter(Mandatory = $false)]
    [switch]$EnableAppInsights,

    [Parameter(Mandatory = $false)]
    [switch]$SkipConfirmation
)

# Script configuration
$ErrorActionPreference = "Stop"
$WarningPreference = "Continue"

# Color output functions
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Header {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

# Main deployment
try {
    Write-Header "Azure APIM Monitoring Scenario Deployment"

    # Display deployment configuration
    Write-ColorOutput "Deployment Configuration:" "Yellow"
    Write-ColorOutput "  Location:            $Location" "Gray"
    Write-ColorOutput "  APIM Service Name:   $ApimServiceName" "Gray"
    Write-ColorOutput "  Publisher Email:     $PublisherEmail" "Gray"
    Write-ColorOutput "  Publisher Name:      $PublisherName" "Gray"
    Write-ColorOutput "  App Insights:        $EnableAppInsights" "Gray"

    # Check if logged in to Azure
    Write-ColorOutput "`nChecking Azure login status..." "Yellow"
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        Write-ColorOutput "Not logged in to Azure. Please login..." "Red"
        az login
        $account = az account show | ConvertFrom-Json
    }
    Write-ColorOutput "✓ Logged in as: $($account.user.name)" "Green"
    Write-ColorOutput "✓ Subscription: $($account.name)" "Green"

    # Confirm deployment
    if (-not $SkipConfirmation) {
        Write-ColorOutput "`nDeployment will take approximately 15-20 minutes." "Yellow"
        $confirmation = Read-Host "Continue with deployment? (y/N)"
        if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
            Write-ColorOutput "Deployment cancelled by user." "Yellow"
            exit 0
        }
    }

    # Start deployment
    Write-Header "Starting Bicep Deployment"
    
    $deploymentName = "apim-monitoring-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    Write-ColorOutput "Deployment name: $deploymentName" "Gray"
    Write-ColorOutput "`nDeploying infrastructure... This will take 15-20 minutes." "Yellow"
    Write-ColorOutput "☕ This is a good time for a coffee break!`n" "Cyan"

    # Build parameters
    $parameters = @(
        "location=$Location"
        "apimServiceName=$ApimServiceName"
        "publisherEmail=$PublisherEmail"
        "publisherName=$PublisherName"
        "enableApplicationInsights=$($EnableAppInsights.IsPresent.ToString().ToLower())"
    )

    # Execute deployment
    $deploymentOutput = az deployment sub create `
        --name $deploymentName `
        --location $Location `
        --template-file "main.bicep" `
        --parameters $parameters `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "✗ Deployment failed!" "Red"
        Write-ColorOutput $deploymentOutput "Red"
        exit 1
    }

    $deployment = $deploymentOutput | ConvertFrom-Json

    Write-ColorOutput "`n✓ Deployment completed successfully!" "Green"

    # Display outputs
    Write-Header "Deployment Outputs"
    
    $outputs = $deployment.properties.outputs
    $gatewayUrl = $outputs.apimGatewayUrl.value
    $portalUrl = $outputs.apimPortalUrl.value
    $devPortalUrl = $outputs.apimDeveloperPortalUrl.value
    $resourceGroup = $outputs.resourceGroupName.value

    Write-ColorOutput "Resource Group:        $resourceGroup" "Gray"
    Write-ColorOutput "APIM Service Name:     $ApimServiceName" "Gray"
    Write-ColorOutput "Gateway URL:           $gatewayUrl" "Cyan"
    Write-ColorOutput "Azure Portal:          $portalUrl" "Cyan"
    Write-ColorOutput "Developer Portal:      $devPortalUrl" "Cyan"

    # Display workbook information
    $workbookName = $outputs.workbookDisplayName.value
    Write-ColorOutput "Monitoring Workbook:   $workbookName" "Green"

    if ($EnableAppInsights) {
        $appInsightsName = $outputs.appInsightsName.value
        Write-ColorOutput "App Insights:          $appInsightsName" "Gray"
    }

    # Display sample APIs
    Write-Header "Sample APIs Deployed"
    Write-ColorOutput "1. Weather API:            $gatewayUrl/weather/{city}" "Gray"
    Write-ColorOutput "2. Product Search:         $gatewayUrl/products/search" "Gray"
    Write-ColorOutput "3. User Validation:        $gatewayUrl/users/validate" "Gray"
    Write-ColorOutput "4. Currency Conversion:    $gatewayUrl/currency/convert" "Gray"
    Write-ColorOutput "5. Health Monitor:         $gatewayUrl/health/status" "Gray"
    Write-ColorOutput "6. Delay Simulator:        $gatewayUrl/simulate/delay" "Gray"

    # Get subscription key
    Write-ColorOutput "`nRetrieving subscription key..." "Yellow"
    $subscriptions = az apim product subscription list `
        --resource-group $resourceGroup `
        --service-name $ApimServiceName `
        --product-id "unlimited" `
        --output json | ConvertFrom-Json

    if ($subscriptions -and $subscriptions.Count -gt 0) {
        $subscriptionId = $subscriptions[0].name
        $keys = az apim product subscription show `
            --resource-group $resourceGroup `
            --service-name $ApimServiceName `
            --product-id "unlimited" `
            --subscription-id $subscriptionId `
            --output json | ConvertFrom-Json

        if ($keys.primaryKey) {
            Write-Header "Quick Test"
            Write-ColorOutput "Use this subscription key for testing:" "Yellow"
            Write-ColorOutput $keys.primaryKey "Cyan"
            
            Write-ColorOutput "`nTest command example:" "Yellow"
            Write-ColorOutput "curl `"$gatewayUrl/health/status`" -H `"Ocp-Apim-Subscription-Key: $($keys.primaryKey)`"" "Gray"
        }
    } else {
        Write-ColorOutput "Note: Get subscription key from Azure Portal" "Yellow"
    }

    # Next steps
    Write-Header "Next Steps"
    Write-ColorOutput "1. 📊 View the monitoring dashboard:" "Cyan"
    Write-ColorOutput "   - Go to Azure Portal > APIM > Workbooks" "Gray"
    Write-ColorOutput "   - Open: $workbookName" "Gray"
    Write-ColorOutput "`n2. Visit the Developer Portal to create subscriptions: $devPortalUrl" "Gray"
    Write-ColorOutput "3. Test the APIs using the examples in README.md" "Gray"
    Write-ColorOutput "4. Monitor API metrics in the Workbook dashboard" "Gray"
    Write-ColorOutput "5. Explore API policies in the Azure Portal" "Gray"

    Write-ColorOutput "`n✓ Deployment complete!`n" "Green"

} catch {
    Write-ColorOutput "`n✗ Error during deployment:" "Red"
    Write-ColorOutput $_.Exception.Message "Red"
    exit 1
}

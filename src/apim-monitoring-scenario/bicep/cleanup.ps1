#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Cleanup Azure API Management Monitoring Scenario

.DESCRIPTION
    This script removes all resources created by the APIM monitoring scenario.

.PARAMETER ResourceGroupName
    Name of the resource group to delete (default: rg-apim-monitoring)

.PARAMETER SkipConfirmation
    Skip deletion confirmation prompt

.EXAMPLE
    .\cleanup.ps1

.EXAMPLE
    .\cleanup.ps1 -ResourceGroupName "rg-apim-monitoring" -SkipConfirmation
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-apim-monitoring",

    [Parameter(Mandatory = $false)]
    [switch]$SkipConfirmation
)

$ErrorActionPreference = "Stop"

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

try {
    Write-Header "Azure APIM Monitoring Scenario Cleanup"

    # Check if logged in to Azure
    Write-ColorOutput "Checking Azure login status..." "Yellow"
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        Write-ColorOutput "Not logged in to Azure. Please login..." "Red"
        az login
        $account = az account show | ConvertFrom-Json
    }
    Write-ColorOutput "✓ Logged in as: $($account.user.name)" "Green"
    Write-ColorOutput "✓ Subscription: $($account.name)" "Green"

    # Check if resource group exists
    Write-ColorOutput "`nChecking if resource group exists..." "Yellow"
    $rgExists = az group exists --name $ResourceGroupName
    
    if ($rgExists -eq "false") {
        Write-ColorOutput "Resource group '$ResourceGroupName' does not exist." "Yellow"
        Write-ColorOutput "Nothing to cleanup." "Green"
        exit 0
    }

    # Get resources in the group
    Write-ColorOutput "✓ Resource group found: $ResourceGroupName" "Green"
    Write-ColorOutput "`nFetching resources..." "Yellow"
    
    $resources = az resource list --resource-group $ResourceGroupName --output json | ConvertFrom-Json
    
    if ($resources.Count -eq 0) {
        Write-ColorOutput "No resources found in the resource group." "Yellow"
    } else {
        Write-ColorOutput "`nResources to be deleted:" "Yellow"
        foreach ($resource in $resources) {
            Write-ColorOutput "  - $($resource.name) ($($resource.type))" "Gray"
        }
    }

    # Confirm deletion
    if (-not $SkipConfirmation) {
        Write-ColorOutput "`n⚠️  WARNING: This will permanently delete all resources in the resource group." "Red"
        Write-ColorOutput "Resource Group: $ResourceGroupName" "Red"
        $confirmation = Read-Host "`nAre you sure you want to continue? (yes/N)"
        if ($confirmation -ne 'yes') {
            Write-ColorOutput "Cleanup cancelled by user." "Yellow"
            exit 0
        }
    }

    # Delete resource group
    Write-Header "Deleting Resource Group"
    Write-ColorOutput "Deleting resource group: $ResourceGroupName" "Yellow"
    Write-ColorOutput "This may take a few minutes...`n" "Gray"

    az group delete --name $ResourceGroupName --yes --no-wait

    Write-ColorOutput "✓ Deletion initiated successfully!" "Green"
    Write-ColorOutput "`nNote: Deletion is running in the background." "Gray"
    Write-ColorOutput "You can check status with:" "Gray"
    Write-ColorOutput "  az group show --name $ResourceGroupName" "Cyan"
    
    Write-ColorOutput "`n✓ Cleanup complete!`n" "Green"

} catch {
    Write-ColorOutput "`n✗ Error during cleanup:" "Red"
    Write-ColorOutput $_.Exception.Message "Red"
    exit 1
}

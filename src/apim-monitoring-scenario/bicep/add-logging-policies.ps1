#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Adds Application Insights logging policies to all APIM APIs
.DESCRIPTION
    This script updates each API policy to include trace logging to Application Insights
#>

param(
    [string]$ResourceGroup = "rg-apim-monitoring",
    [string]$ApimName = "your-apim-instance",
    [string]$LoggerName = "applicationinsights-logger"
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Adding Application Insights Logging to APIM APIs" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Get subscription ID
$subscriptionId = (az account show --query id -o tsv)

# List of APIs to update
$apis = @(
    @{Name = "weather-api"; DisplayName = "Weather Data API"}
    @{Name = "product-search-api"; DisplayName = "Product Search API"}
    @{Name = "user-validation-api"; DisplayName = "User Validation API"}
    @{Name = "currency-conversion-api"; DisplayName = "Currency Conversion API"}
    @{Name = "health-monitor-api"; DisplayName = "Health Monitor API"}
    @{Name = "delay-simulator-api"; DisplayName = "Delay Simulator API"}
)

foreach ($api in $apis) {
    Write-Host "Updating $($api.DisplayName)..." -ForegroundColor Yellow
    
    # Get current policy
    $policyUri = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/apis/$($api.Name)/policies/policy?api-version=2023-05-01-preview"
    
    try {
        $currentPolicy = az rest --method get --uri $policyUri --query "properties.value" -o tsv 2>$null
        
        if ($LASTEXITCODE -eq 0 -and $currentPolicy) {
            # Check if logging is already added
            if ($currentPolicy -match "trace") {
                Write-Host "  Logging already exists, skipping..." -ForegroundColor Green
                continue
            }
            
            # Add logging to inbound section (after <base />)
            $updatedPolicy = $currentPolicy -replace '(<inbound>\s*<base\s*/>\s*)', @"
`$1
    <trace source="$($api.Name)" severity="information">
      <message>@("Request received: " + context.Request.Method + " " + context.Request.Url.Path)</message>
      <metadata name="OperationId" value="@(context.RequestId)" />
      <metadata name="Api" value="$($api.DisplayName)" />
      <metadata name="ClientIP" value="@(context.Request.IpAddress)" />
    </trace>
"@
            
            # Add logging to outbound section (before </outbound>)
            $updatedPolicy = $updatedPolicy -replace '(\s*</outbound>)', @"
    <trace source="$($api.Name)" severity="information">
      <message>@("Response sent: " + context.Response.StatusCode.ToString())</message>
      <metadata name="OperationId" value="@(context.RequestId)" />
      <metadata name="StatusCode" value="@(context.Response.StatusCode.ToString())" />
      <metadata name="Duration" value="@((DateTime.UtcNow - context.Variables.GetValueOrDefault<DateTime>("RequestTime", DateTime.UtcNow)).TotalMilliseconds.ToString())" />
    </trace>
`$1
"@
            
            # Add request time tracking at start of inbound (right after <base />)
            $updatedPolicy = $updatedPolicy -replace '(<inbound>\s*<base\s*/>\s*)', @"
`$1
    <set-variable name="RequestTime" value="@(DateTime.UtcNow)" />
"@
            
            # Save updated policy
            $tempFile = [System.IO.Path]::GetTempFileName()
            $updatedPolicy | Out-File -FilePath $tempFile -Encoding utf8 -NoNewline
            
            # Update policy in APIM
            $updateBody = @{
                properties = @{
                    value = $updatedPolicy
                    format = "xml"
                }
            } | ConvertTo-Json -Depth 10 -Compress
            
            $updateBody | Out-File -FilePath "$tempFile.json" -Encoding utf8 -NoNewline
            
            az rest --method put --uri $policyUri --body "@$tempFile.json" | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Successfully added logging!" -ForegroundColor Green
            } else {
                Write-Host "  Failed to update policy" -ForegroundColor Red
            }
            
            # Cleanup
            Remove-Item $tempFile -ErrorAction SilentlyContinue
            Remove-Item "$tempFile.json" -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Host "  Error: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Configuring APIM Diagnostic Settings" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Enable diagnostic settings for APIM service
$diagnosticUri = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/providers/Microsoft.Insights/diagnosticSettings/applicationinsights?api-version=2021-05-01-preview"

$logAnalyticsId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/log-appi-$ApimName"
$appInsightsId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/components/appi-$ApimName"

$diagnosticSettings = @{
    properties = @{
        workspaceId = $logAnalyticsId
        logs = @(
            @{
                category = "GatewayLogs"
                enabled = $true
            }
            @{
                categoryGroup = "allLogs"
                enabled = $true
            }
        )
        metrics = @(
            @{
                category = "AllMetrics"
                enabled = $true
            }
        )
    }
} | ConvertTo-Json -Depth 10

$tempDiagFile = [System.IO.Path]::GetTempFileName()
$diagnosticSettings | Out-File -FilePath $tempDiagFile -Encoding utf8 -NoNewline

Write-Host "Enabling diagnostic settings..." -ForegroundColor Yellow
az rest --method put --uri $diagnosticUri --body "@$tempDiagFile" | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "Successfully enabled diagnostic settings!" -ForegroundColor Green
} else {
    Write-Host "Failed to enable diagnostic settings" -ForegroundColor Red
}

Remove-Item $tempDiagFile -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Done!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Your APIs now log to Application Insights:" -ForegroundColor White
Write-Host "  - Request method and URL" -ForegroundColor Gray
Write-Host "  - Response status codes" -ForegroundColor Gray
Write-Host "  - Request duration" -ForegroundColor Gray
Write-Host "  - Client IP addresses" -ForegroundColor Gray
Write-Host "  - Operation IDs for tracing" -ForegroundColor Gray
Write-Host ""
Write-Host "View logs in Azure Portal:" -ForegroundColor White
Write-Host "  Portal -> Application Insights -> appi-$ApimName -> Logs" -ForegroundColor Cyan
Write-Host ""

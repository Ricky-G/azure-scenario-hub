# PowerShell deployment script for Azure Functions
param(
    [string]$ResourceGroup = $env:RESOURCE_GROUP
)

# Check if RESOURCE_GROUP is set
if ([string]::IsNullOrEmpty($ResourceGroup)) {
    Write-Error "Error: RESOURCE_GROUP is not set"
    Write-Host "Please run: `$env:RESOURCE_GROUP='rg-ais-loadtest'"
    exit 1
}

Write-Host "=========================================="
Write-Host "Deploying Azure Functions"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "=========================================="
Write-Host ""

# Get function app names from deployment
Write-Host "Getting function app names from Azure deployment..."
$AUDITS_ADAPTOR = az deployment group show -g $ResourceGroup -n main --query 'properties.outputs.auditsAdaptorFunctionName.value' -o tsv
$AUDIT_STORE = az deployment group show -g $ResourceGroup -n main --query 'properties.outputs.auditStoreFunctionName.value' -o tsv
$HISTORY_ADAPTOR = az deployment group show -g $ResourceGroup -n main --query 'properties.outputs.historyAdaptorFunctionName.value' -o tsv
$HISTORY_STORE = az deployment group show -g $ResourceGroup -n main --query 'properties.outputs.historyStoreFunctionName.value' -o tsv
$AVAILABILITY_CHECKER = az deployment group show -g $ResourceGroup -n main --query 'properties.outputs.availabilityCheckerFunctionName.value' -o tsv

Write-Host "Function app names retrieved:"
Write-Host "  - Audits Adaptor: $AUDITS_ADAPTOR"
Write-Host "  - Audit Store: $AUDIT_STORE"
Write-Host "  - History Adaptor: $HISTORY_ADAPTOR"
Write-Host "  - History Store: $HISTORY_STORE"
Write-Host "  - Availability Checker: $AVAILABILITY_CHECKER"
Write-Host ""

# Build all functions
Write-Host "Building all functions..."
$functions = @("audits-adaptor", "audit-store", "history-adaptor", "history-store", "availability-checker")
foreach ($func in $functions) {
    Write-Host "Building $func..."
    Push-Location "functions\$func"
    dotnet build -c Release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build $func"
        Pop-Location
        exit 1
    }
    Pop-Location
}
Write-Host "All functions built successfully!"
Write-Host ""

# Deploy all functions
Write-Host "Deploying all functions..."
$jobs = @()

# Start deployments in background
$jobs += Start-Job -ScriptBlock {
    param($path, $appName)
    Set-Location $path
    func azure functionapp publish $appName --dotnet-isolated
} -ArgumentList "$PWD\functions\audits-adaptor", $AUDITS_ADAPTOR

$jobs += Start-Job -ScriptBlock {
    param($path, $appName)
    Set-Location $path
    func azure functionapp publish $appName --dotnet-isolated
} -ArgumentList "$PWD\functions\audit-store", $AUDIT_STORE

$jobs += Start-Job -ScriptBlock {
    param($path, $appName)
    Set-Location $path
    func azure functionapp publish $appName --dotnet-isolated
} -ArgumentList "$PWD\functions\history-adaptor", $HISTORY_ADAPTOR

$jobs += Start-Job -ScriptBlock {
    param($path, $appName)
    Set-Location $path
    func azure functionapp publish $appName --dotnet-isolated
} -ArgumentList "$PWD\functions\history-store", $HISTORY_STORE

$jobs += Start-Job -ScriptBlock {
    param($path, $appName)
    Set-Location $path
    func azure functionapp publish $appName --dotnet-isolated
} -ArgumentList "$PWD\functions\availability-checker", $AVAILABILITY_CHECKER

# Wait for all jobs to complete
Write-Host "Waiting for all deployments to complete..."
$jobs | Wait-Job

# Check job results
$failed = $false
foreach ($job in $jobs) {
    if ($job.State -ne "Completed") {
        $failed = $true
        Write-Error "Deployment job failed"
        $job | Receive-Job
    }
}

$jobs | Remove-Job

if ($failed) {
    Write-Error "One or more deployments failed"
    exit 1
}

Write-Host ""
Write-Host "=========================================="
Write-Host "All functions deployed successfully!"
Write-Host "=========================================="
Write-Host ""
Write-Host "Your Azure Integration Services Load Test environment is ready!"
Write-Host ""
Write-Host "Test the deployment by visiting:"
Write-Host "  - Audits API: https://$AUDITS_ADAPTOR.azurewebsites.net/api/health"
Write-Host "  - Audit Store: https://$AUDIT_STORE.azurewebsites.net/api/health"
Write-Host "  - History API: https://$HISTORY_ADAPTOR.azurewebsites.net/api/health"
Write-Host "  - History Store: https://$HISTORY_STORE.azurewebsites.net/api/health"
Write-Host "  - Availability: https://$AVAILABILITY_CHECKER.azurewebsites.net/api/health"
Write-Host ""
# Variables
$ResourceGroupName = "rg-function-unzip-large-files"
$FunctionDir = "function-unzip-large-zip-files"

# Get function app name from deployment
Write-Host "Getting function app name..." -ForegroundColor Green
$FunctionAppName = az functionapp list --resource-group $ResourceGroupName --query "[0].name" -o tsv

if ([string]::IsNullOrEmpty($FunctionAppName)) {
    Write-Host "Error: No function app found in resource group $ResourceGroupName" -ForegroundColor Red
    Write-Host "Please run .\deploy-infra.ps1 first" -ForegroundColor Yellow
    exit 1
}

Write-Host "Function App Name: $FunctionAppName" -ForegroundColor Yellow

# Install Python dependencies
Write-Host "Installing Python dependencies..." -ForegroundColor Green
Set-Location $FunctionDir

# Clean up existing packages to avoid conflicts
if (Test-Path ".python_packages") {
    Remove-Item ".python_packages" -Recurse -Force
}

# Install packages with upgrade flag
pip install --target=".python_packages/lib/site-packages" --upgrade -r requirements.txt

# Create deployment package
Write-Host "Creating deployment package..." -ForegroundColor Green

# Create a temporary directory for deployment files
$TempDir = "temp_deploy"
if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir | Out-Null

# Copy files excluding unwanted items
$ExcludePatterns = @("*.env", "__pycache__", ".venv", ".vscode", "*.pyc", "*.pyo", "temp_deploy")

Get-ChildItem -Path . -Recurse | Where-Object {
    $item = $_
    $shouldExclude = $false
    
    foreach ($pattern in $ExcludePatterns) {
        if ($item.Name -like $pattern -or $item.FullName -like "*\$pattern\*" -or $item.FullName -like "*/$pattern/*") {
            $shouldExclude = $true
            break
        }
    }
    
    -not $shouldExclude
} | ForEach-Object {
    $relativePath = $_.FullName.Substring((Get-Location).Path.Length + 1)
    $destinationPath = Join-Path $TempDir $relativePath
    $destinationDir = Split-Path $destinationPath -Parent
    
    if (-not (Test-Path $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }
    
    if (-not $_.PSIsContainer) {
        Copy-Item $_.FullName $destinationPath
    }
}

# Create the zip file from the temp directory
Compress-Archive -Path "$TempDir\*" -DestinationPath ..\function-app.zip -Force -CompressionLevel Optimal

# Clean up temp directory
Remove-Item $TempDir -Recurse -Force

# Deploy to Azure
Write-Host "Deploying function to Azure..." -ForegroundColor Green
Set-Location ..

if (-not (Test-Path "function-app.zip")) {
    Write-Host "Error: function-app.zip was not created successfully" -ForegroundColor Red
    exit 1
}

Write-Host "Deploying ZIP package to Function App..." -ForegroundColor Yellow
az functionapp deployment source config-zip `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --src function-app.zip `
    --build-remote false

if ($LASTEXITCODE -eq 0) {
    Write-Host "Function deployed successfully!" -ForegroundColor Green
} else {
    Write-Host "Function deployment failed! Exit code: $LASTEXITCODE" -ForegroundColor Red
    Write-Host "Check the Azure portal for more deployment details." -ForegroundColor Yellow
}

# Clean up
if (Test-Path "function-app.zip") {
    Remove-Item function-app.zip
}

Write-Host ""
Write-Host "Function deployment completed!" -ForegroundColor Green
Write-Host "Your function is now live at: https://$FunctionAppName.azurewebsites.net" -ForegroundColor Yellow
Write-Host ""
Write-Host "To test:" -ForegroundColor Cyan
Write-Host "1. Upload a password-protected ZIP file to the 'zipped' container" -ForegroundColor White
Write-Host "2. The function will automatically extract files to the 'unzipped' container" -ForegroundColor White
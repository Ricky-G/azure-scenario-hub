Write-Host "Initializing Terraform..." -ForegroundColor Green
terraform init

Write-Host "Planning Terraform deployment..." -ForegroundColor Green
terraform plan

$confirm = Read-Host "Do you want to apply these changes? (yes/no)"
if ($confirm -eq "yes") {
    Write-Host "Applying Terraform configuration..." -ForegroundColor Green
    terraform apply -auto-approve
    
    Write-Host ""
    Write-Host "Deployment complete!" -ForegroundColor Green
    Write-Host "To get the storage connection string, run:" -ForegroundColor Yellow
    Write-Host "terraform output -raw storage_account_primary_connection_string" -ForegroundColor Cyan
    
    # Get outputs
    $functionAppName = terraform output -raw function_app_name
    Write-Host ""
    Write-Host "Function App Name: $functionAppName" -ForegroundColor Yellow
} else {
    Write-Host "Deployment cancelled." -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deploying Infrastructure using Bicep" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Set-Location bicep
.\deploy.ps1
Set-Location ..

Write-Host ""
Write-Host "Infrastructure deployment completed!" -ForegroundColor Green
Write-Host "You can now deploy the function app using .\deploy-function.ps1" -ForegroundColor Yellow
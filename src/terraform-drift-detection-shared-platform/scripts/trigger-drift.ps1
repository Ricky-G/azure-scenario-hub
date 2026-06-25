#!/usr/bin/env pwsh
# =============================================================================
# Trigger drift (PowerShell)
# =============================================================================
# Crosses "the line": modifies a TF-MANAGED attribute (a tag) on the platform
# storage account. Unlike adding child resources, this DOES show up as drift,
# because Terraform manages the `tags` collection on this resource exhaustively.
#
# After running this, run check-drift to see Terraform report the difference.
# =============================================================================

$ErrorActionPreference = 'Stop'

$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$terraformDir = Join-Path (Join-Path $scriptDir '..') 'terraform'

Push-Location $terraformDir
try {
    $storageId = terraform output -raw storage_account_id
}
finally {
    Pop-Location
}

Write-Host "Adding an out-of-band tag to the storage account (Terraform manages tags)..." -ForegroundColor Yellow
az resource tag --ids $storageId --tags AddedByAppTeam=drift-test --is-incremental | Out-Null

Write-Host ''
Write-Host 'Out-of-band tag applied.' -ForegroundColor Green
Write-Host 'Now run check-drift - Terraform WILL report drift on the tags attribute.' -ForegroundColor Green

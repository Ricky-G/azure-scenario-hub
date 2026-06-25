#!/usr/bin/env pwsh
# =============================================================================
# Drift check (PowerShell)
# =============================================================================
# Runs a full plan against the platform Terraform state.
#
# `terraform plan` refreshes from real Azure and compares it to the committed
# configuration - the same "does reality match config?" question that Terraform
# Cloud's drift detection / health assessments answer. We use a full plan (not
# `-refresh-only`) so that `lifecycle { ignore_changes }` is honored, which is
# how TFC drift detection behaves too.
# =============================================================================

$ErrorActionPreference = 'Stop'

$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$terraformDir = Join-Path (Join-Path $scriptDir '..') 'terraform'

Write-Host 'Running terraform plan to detect drift against the committed configuration...' -ForegroundColor Cyan
Push-Location $terraformDir
try {
    terraform plan
}
finally {
    Pop-Location
}

#!/usr/bin/env bash
# =============================================================================
# Drift check (Bash)
# =============================================================================
# Runs a full plan against the platform Terraform state.
#
# `terraform plan` refreshes from real Azure and compares it to the committed
# configuration - the same "does reality match config?" question that Terraform
# Cloud's drift detection / health assessments answer. We use a full plan (not
# `-refresh-only`) so that `lifecycle { ignore_changes }` is honored, which is
# how TFC drift detection behaves too.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

echo "Running terraform plan to detect drift against the committed configuration..."
pushd "$TERRAFORM_DIR" > /dev/null
terraform plan
popd > /dev/null

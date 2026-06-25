#!/usr/bin/env bash
# =============================================================================
# Trigger drift (Bash)
# =============================================================================
# Crosses "the line": modifies a TF-MANAGED attribute (a tag) on the platform
# storage account. Unlike adding child resources, this DOES show up as drift,
# because Terraform manages the `tags` collection on this resource exhaustively.
#
# After running this, run check-drift to see Terraform report the difference.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

pushd "$TERRAFORM_DIR" > /dev/null
STORAGE_ID=$(terraform output -raw storage_account_id)
popd > /dev/null

echo "Adding an out-of-band tag to the storage account (Terraform manages tags)..."
az resource tag --ids "$STORAGE_ID" --tags AddedByAppTeam=drift-test --is-incremental > /dev/null

echo ""
echo "Out-of-band tag applied."
echo "Now run check-drift - Terraform WILL report drift on the tags attribute."

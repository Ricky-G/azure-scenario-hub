# -----------------------------------------------------------------------------
# Storage Account (platform-owned)
# -----------------------------------------------------------------------------
# Cheapest viable config: Standard / LRS / StorageV2. Public blob access is
# disabled per repo security standards.
#
# DRIFT NOTE: Terraform manages the ACCOUNT, not its blob containers. When the
# app team later adds a container (Microsoft.Storage/.../blobServices/containers),
# that is a SEPARATE ARM resource that is not part of this resource's schema, so
# `terraform plan` will NOT report drift for it.
# -----------------------------------------------------------------------------
resource "azurerm_storage_account" "main" {
  name                            = local.storage_name
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  access_tier                     = "Hot"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  # Disable shared-key auth (Azure AD only). Aligns with the common secure-baseline
  # policy and the repo's managed-identity-first security standard.
  shared_access_key_enabled = false

  tags = local.common_tags
}

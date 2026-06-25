# -----------------------------------------------------------------------------
# Cosmos DB account (platform-owned)
# -----------------------------------------------------------------------------
# Cheapest viable config: SQL (Core) API in SERVERLESS mode, single region, no
# zone redundancy. Serverless bills per-request, so an idle account costs ~$0.
#
# DRIFT NOTE: Terraform manages the ACCOUNT only. When the app team later adds a
# SQL database / container (separate ARM resources under the account), those are
# NOT part of azurerm_cosmosdb_account's schema, so `terraform plan` will NOT
# report drift for them.
# -----------------------------------------------------------------------------
resource "azurerm_cosmosdb_account" "main" {
  name                = local.cosmos_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  # Keyless (Entra-only) data-plane auth. Many secure subscriptions enforce this
  # via policy; setting it explicitly keeps the plan clean and is the secure default.
  local_authentication_disabled = true

  # Serverless = the cheapest capacity mode for low / spiky workloads.
  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  tags = local.common_tags
}

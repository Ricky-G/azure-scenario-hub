# -----------------------------------------------------------------------------
# Azure AI Foundry account (platform-owned)
# -----------------------------------------------------------------------------
# Modeled with the azapi provider so we get the modern, project-capable Foundry
# resource (Microsoft.CognitiveServices/accounts, kind=AIServices) with
# `allowProjectManagement = true`. There is no fixed hourly cost - AIServices
# billing is pay-per-token, so an idle account costs ~$0.
#
# DRIFT NOTE - the key one for this scenario:
# azapi only reconciles the fields declared in `body` below. When the app team
# later creates a Foundry PROJECT (Microsoft.CognitiveServices/accounts/projects,
# a separate child resource), it does not change any field in this body, so
# `terraform plan` will NOT report drift for it.
# -----------------------------------------------------------------------------
resource "azapi_resource" "foundry" {
  # NOTE: If this preview API version is retired, bump it to a current
  # Microsoft.CognitiveServices/accounts version that supports project management.
  type      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name      = local.foundry_name
  parent_id = azurerm_resource_group.main.id
  location  = azurerm_resource_group.main.location
  tags      = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      # Required so that PROJECTS can be created under this account.
      allowProjectManagement = true
      # A custom subdomain is required for AIServices + project management.
      customSubDomainName = local.foundry_name
      publicNetworkAccess = "Enabled"
      # Keyless (Entra-only) auth. Many secure subscriptions enforce this via
      # policy; setting it explicitly keeps the plan clean and is the secure default.
      disableLocalAuth = true
    }
  }

  # Preview API schemas can be incomplete; skip client-side validation to avoid
  # false-positive errors on newer properties.
  schema_validation_enabled = false
}

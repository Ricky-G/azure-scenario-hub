# Key Vault
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Disable public access
  public_network_access_enabled = false
  
  # Enable RBAC authorization
  enable_rbac_authorization = true
  
  # Network ACLs
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
  
  tags = local.tags
}

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Sample secret in Key Vault
resource "azurerm_key_vault_secret" "demo" {
  name         = "demo-secret"
  value        = "Hello from Key Vault via Private Endpoint!"
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    azurerm_role_assignment.key_vault_secrets_user
  ]
}

# Private Endpoint for Key Vault
resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-${local.key_vault_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  
  private_service_connection {
    name                           = "pe-${local.key_vault_name}"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }
  
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }
  
  tags = local.tags
}

# Role Assignment: Key Vault Secrets User for Managed Identity
resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}
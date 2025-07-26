# User Assigned Managed Identity
resource "azurerm_user_assigned_identity" "main" {
  name                = local.identity_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.tags
}
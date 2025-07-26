resource "azurerm_storage_container" "source" {
  name                  = var.source_container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "destination" {
  name                  = var.destination_container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}
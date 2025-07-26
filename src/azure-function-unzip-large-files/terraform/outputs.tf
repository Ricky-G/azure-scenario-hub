output "storage_account_name" {
  description = "Name of the created storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "source_container_name" {
  description = "Name of the source container"
  value       = azurerm_storage_container.source.name
}

output "destination_container_name" {
  description = "Name of the destination container"
  value       = azurerm_storage_container.destination.name
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "function_app_name" {
  description = "Name of the function app"
  value       = azurerm_linux_function_app.main.name
}

output "application_insights_name" {
  description = "Name of the application insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for application insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}
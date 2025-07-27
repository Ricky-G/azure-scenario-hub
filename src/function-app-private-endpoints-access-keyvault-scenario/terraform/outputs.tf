output "function_app_name" {
  description = "The name of the Function App"
  value       = azurerm_windows_function_app.main.name
}

output "function_app_url" {
  description = "The default hostname of the Function App"
  value       = "https://${azurerm_windows_function_app.main.default_hostname}"
}

output "key_vault_name" {
  description = "The name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_url" {
  description = "The URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "user_assigned_identity_id" {
  description = "The ID of the User Assigned Managed Identity"
  value       = azurerm_user_assigned_identity.main.id
}

output "user_assigned_identity_client_id" {
  description = "The Client ID of the User Assigned Managed Identity"
  value       = azurerm_user_assigned_identity.main.client_id
}

output "app_insights_name" {
  description = "The name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "app_insights_instrumentation_key" {
  description = "The instrumentation key of the Application Insights instance"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "vnet_name" {
  description = "The name of the Virtual Network"
  value       = azurerm_virtual_network.main.name
}

output "private_endpoint_name" {
  description = "The name of the Key Vault private endpoint"
  value       = azurerm_private_endpoint.key_vault.name
}
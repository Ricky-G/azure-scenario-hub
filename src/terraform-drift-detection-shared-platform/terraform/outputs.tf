# -----------------------------------------------------------------------------
# Outputs - consumed by the app-team deploy script and the drift helper scripts.
# -----------------------------------------------------------------------------
output "resource_group_name" {
  description = "Resource group that holds all platform-owned resources."
  value       = azurerm_resource_group.main.name
}

output "storage_account_name" {
  description = "Platform-owned storage account name."
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Platform-owned storage account resource ID (used by trigger-drift)."
  value       = azurerm_storage_account.main.id
}

output "cosmos_account_name" {
  description = "Platform-owned Cosmos DB account name."
  value       = azurerm_cosmosdb_account.main.name
}

output "foundry_account_name" {
  description = "Platform-owned Azure AI Foundry account name."
  value       = azapi_resource.foundry.name
}

output "foundry_account_id" {
  description = "Platform-owned Azure AI Foundry account resource ID."
  value       = azapi_resource.foundry.id
}

output "redis_name" {
  description = "Platform-owned Redis cache name (null when deploy_redis = false)."
  value       = var.deploy_redis ? azurerm_redis_cache.main[0].name : null
}

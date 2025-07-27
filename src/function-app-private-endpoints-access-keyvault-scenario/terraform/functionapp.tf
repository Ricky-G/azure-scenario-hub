# Storage Account for Function App
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Security settings
  https_traffic_only_enabled = true
  default_to_oauth_authentication = true
  
  tags = local.tags
}

# App Service Plan
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Windows"
  sku_name            = var.sku
  
  tags = local.tags
}

# Function App
resource "azurerm_windows_function_app" "main" {
  name                = local.function_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Enable VNet integration
  virtual_network_subnet_id = azurerm_subnet.function_app.id
  
  # Route all traffic through VNet
  vnet_route_all_enabled = true
  
  # HTTPS only
  https_only = true
  
  # Managed Identity
  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.main.id
    ]
  }
  
  site_config {
    ftps_state             = "FtpsOnly"
    minimum_tls_version    = "1.2"
    vnet_route_all_enabled = true
    
    # CORS configuration (empty for security)
    cors {
      allowed_origins = []
      support_credentials = false
    }
    
    application_stack {
      node_version = "~18"
    }
  }
  
  app_settings = {
    # Function runtime settings
    "FUNCTIONS_EXTENSION_VERSION" = "~4"
    "FUNCTIONS_WORKER_RUNTIME"    = var.runtime
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    
    # Storage account configuration (using managed identity)
    "AzureWebJobsStorage__accountName" = azurerm_storage_account.main.name
    "AzureWebJobsStorage__credential"  = "managedidentity"
    "AzureWebJobsStorage__clientId"    = azurerm_user_assigned_identity.main.client_id
    
    # Content share configuration (still requires connection string)
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTSHARE"                      = lower(local.function_app_name)
    
    # Key Vault configuration
    "KEY_VAULT_URL"   = azurerm_key_vault.main.vault_uri
    "AZURE_CLIENT_ID" = azurerm_user_assigned_identity.main.client_id
    
    # Application Insights
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
  }
  
  tags = merge(local.tags, {
    "azd-service-name" = "api"
  })
  
  depends_on = [
    azurerm_private_endpoint.key_vault,
    azurerm_role_assignment.storage_blob_contributor
  ]
}

# Role Assignment: Storage Blob Data Contributor for Managed Identity
resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}
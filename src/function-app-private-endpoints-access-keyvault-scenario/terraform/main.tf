terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

# Generate unique suffix for resource names
resource "random_string" "resource_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-func-keyvault-demo-${random_string.resource_suffix.result}"
  location = var.location
  
  tags = local.tags
}

# Local variables
locals {
  tags = {
    "azd-env-name" = "demo"
    "scenario"     = "function-keyvault-private-endpoint"
  }
  
  # Resource names
  function_app_name    = var.app_name != "" ? var.app_name : "func-privateep-${random_string.resource_suffix.result}"
  app_service_plan_name = "asp-${local.function_app_name}"
  storage_account_name  = "st${random_string.resource_suffix.result}"
  key_vault_name       = "kv-${random_string.resource_suffix.result}"
  vnet_name            = "vnet-${local.function_app_name}"
  app_insights_name    = "ai-${local.function_app_name}"
  identity_name        = "id-${local.function_app_name}"
}
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.0"
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

locals {
  function_app_name         = var.function_app_name != "" ? var.function_app_name : "func-unzip-${substr(md5(azurerm_resource_group.main.id), 0, 8)}"
  app_service_plan_name     = var.app_service_plan_name != "" ? var.app_service_plan_name : "asp-unzip-${substr(md5(azurerm_resource_group.main.id), 0, 8)}"
  application_insights_name = var.application_insights_name != "" ? var.application_insights_name : "appi-unzip-${substr(md5(azurerm_resource_group.main.id), 0, 8)}"
}

resource "azurerm_storage_account" "main" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  min_tls_version          = "TLS1_2"
  
  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
}
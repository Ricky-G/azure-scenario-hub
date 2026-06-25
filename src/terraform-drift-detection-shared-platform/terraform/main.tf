# =============================================================================
# PLATFORM TEAM - Landing zone base resources
# =============================================================================
# This Terraform configuration represents the resources a platform team owns and
# manages from their own Terraform Cloud workspace / pipeline. It deploys the
# shared "AI landing zone" building blocks (Storage, Cosmos DB, Redis, Foundry)
# that app teams are then expected to build ON TOP OF (their own containers,
# databases, and Foundry projects).
#
# The whole point of this scenario is to discover WHERE drift is detected when
# an app team adds child resources out-of-band. See README.md for the walkthrough.
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    # azapi is used for the modern, project-capable Azure AI Foundry account.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  features {}

  # Many secure subscriptions enforce a policy that blocks shared-key auth on
  # storage accounts. Use Azure AD (the logged-in principal / CI identity) for
  # data-plane operations so the provider never falls back to account keys.
  storage_use_azuread = true
}

provider "azapi" {}

# Random suffix keeps globally-unique resource names collision-free.
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-drift-demo-${random_string.suffix.result}"
  location = var.location
  tags     = local.common_tags
}

locals {
  name_suffix = random_string.suffix.result

  # Derived, deterministic resource names (never asked of the user).
  storage_name = "stdrift${local.name_suffix}" # 3-24 lowercase alphanumeric
  cosmos_name  = "cosmos-drift-${local.name_suffix}"
  redis_name   = "redis-drift-${local.name_suffix}"
  foundry_name = "foundry-drift-${local.name_suffix}"

  # Tags are managed EXHAUSTIVELY by Terraform here. That matters: an out-of-band
  # change to this tag set is exactly what crosses "the line" into drift.
  common_tags = {
    Environment = "Development"
    Project     = "AzureScenarioHub"
    Scenario    = "terraform-drift-detection-shared-platform"
    ManagedBy   = "Terraform"
    Owner       = "PlatformTeam"
  }
}

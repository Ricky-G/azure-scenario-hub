variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-function-unzip-large-files"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "storage_account_name" {
  description = "Name of the storage account"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be between 3 and 24 characters, and can only contain lowercase letters and numbers."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Invalid replication type specified."
  }
}

variable "source_container_name" {
  description = "Name of the source container for ZIP files"
  type        = string
  default     = "zipped"
}

variable "destination_container_name" {
  description = "Name of the destination container for extracted files"
  type        = string
  default     = "unzipped"
}

variable "function_app_name" {
  description = "Name of the function app"
  type        = string
  default     = ""
}

variable "app_service_plan_name" {
  description = "Name of the app service plan"
  type        = string
  default     = ""
}

variable "application_insights_name" {
  description = "Name of the application insights instance"
  type        = string
  default     = ""
}

variable "zip_password" {
  description = "Password for the ZIP files"
  type        = string
  sensitive   = true
  # No default value - must be provided during deployment
}
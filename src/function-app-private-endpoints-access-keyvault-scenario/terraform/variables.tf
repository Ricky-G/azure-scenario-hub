variable "app_name" {
  description = "The name of the function app that you wish to create."
  type        = string
  default     = ""
}

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "The name of the resource group. If not specified, a name will be generated."
  type        = string
  default     = ""
}

variable "runtime" {
  description = "The language worker runtime to load in the function app."
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "dotnet", "java"], var.runtime)
    error_message = "The runtime must be one of: node, dotnet, java"
  }
}

variable "sku" {
  description = "The pricing tier for the hosting plan (VNet integration requires EP1 or higher)"
  type        = string
  default     = "EP1"
  
  validation {
    condition     = contains(["EP1", "EP2", "EP3"], var.sku)
    error_message = "The SKU must be one of: EP1, EP2, EP3 (VNet integration requires Elastic Premium)"
  }
}
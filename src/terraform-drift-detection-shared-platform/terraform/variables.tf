variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Optional explicit resource group name. Leave empty to auto-generate a unique name."
  type        = string
  default     = ""
}

variable "deploy_redis" {
  description = "Whether to deploy Azure Cache for Redis (Basic C0). Adds ~$16/mo and ~15-20 min of provisioning time. Set to false for a faster, cheaper run."
  type        = bool
  default     = true
}

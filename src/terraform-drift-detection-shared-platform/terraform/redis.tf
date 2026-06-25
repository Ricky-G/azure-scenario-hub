# -----------------------------------------------------------------------------
# Azure Cache for Redis (platform-owned, optional)
# -----------------------------------------------------------------------------
# Cheapest real Redis SKU: Basic C0 (250 MB). Note: Basic has no SLA and Redis
# provisioning takes ~15-20 minutes. Toggle off with `deploy_redis = false`.
#
# DRIFT NOTE: Redis has no app-team child resources in this scenario, so it acts
# as the experimental "control" - it should never show drift.
# -----------------------------------------------------------------------------
resource "azurerm_redis_cache" "main" {
  count = var.deploy_redis ? 1 : 0

  name                = local.redis_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  capacity            = 0
  family              = "C"
  sku_name            = "Basic"
  minimum_tls_version = "1.2"
  enable_non_ssl_port = false

  tags = local.common_tags
}

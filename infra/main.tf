locals {
  tags = merge({
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }, var.owner != "" ? { owner = var.owner } : {}, var.tags)
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project}-${var.environment}-${var.location_short}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_static_web_app" "main" {
  name                = "stapp-${var.project}-${var.environment}-${var.location_short}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku_tier            = var.sku_tier
  sku_size            = var.sku_tier
  tags                = local.tags
}

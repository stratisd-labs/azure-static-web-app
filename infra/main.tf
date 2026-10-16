locals {
  tags = merge({
    project     = var.project
    environment = "prod"
    managed_by  = "terraform"
  }, var.tags)
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project}-prod-weu"
  location = var.location
  tags     = local.tags
}

resource "azurerm_static_web_app" "main" {
  name                = "stapp-${var.project}-prod-weu"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku_tier            = var.sku_tier
  sku_size            = var.sku_tier
  tags                = local.tags
}

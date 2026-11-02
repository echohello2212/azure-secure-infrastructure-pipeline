#Public IP for the application gateway, Standard SKU. Static allocation required
resource "azurerm_public_ip" "pip_appgw" {
  name                = "pip-appgw"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku                 = "Standard"
  allocation_method   = "Static"
}

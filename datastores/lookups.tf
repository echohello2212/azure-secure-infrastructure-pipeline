data "azurerm_resource_group" "rg_asip" {
  name = "rg-asip"
}

data "azurerm_subnet" "snet_endpoints" {
  name                 = "snet-endpoints"
  virtual_network_name = "vnet-asip"
  resource_group_name  = data.azurerm_resource_group.rg_asip.name
}

data "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = data.azurerm_resource_group.rg_asip.name
}
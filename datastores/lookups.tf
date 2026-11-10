data "azurerm_resource_group" "rg_asip" {
  name = "rg-asip"
}

data "azurerm_subnet" "endpoints_subnet" {
  name                 = "snet-endpoints"
  virtual_network_name = "vnet-asip"
  resource_group_name  = data.azurerm_resource_group.rg_asip.name
}

data "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = data.azurerm_resource_group.rg_asip.name
}

data "azurerm_private_dns_zone" "db" {
  name                = "privatelink.database.windows.net"
  resource_group_name = data.azurerm_resource_group.rg_asip.name
}


data "azurerm_client_config" "current" {

}
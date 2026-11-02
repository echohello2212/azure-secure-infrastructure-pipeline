#Looks up data associated with the resource group
data "azurerm_resource_group" "rg" {
  name = "rg-asip"
}

#Looks up the bastion subnet from the network stack, its ID is used by the bastion host
data "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  virtual_network_name = "vnet-asip"
  resource_group_name  = data.azurerm_resource_group.rg.name
}

#Looks up the app gateway subnet from the network stack, its ID is used by the application gateway
data "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  virtual_network_name = "vnet-asip"
  resource_group_name  = data.azurerm_resource_group.rg.name
}
#Looks up the frontend NIC. Private IP, appgw's backend address. Compute must be deployed first
data "azurerm_network_interface" "nic_frontend_1" {
  name                = "nic-frontend-1"
  resource_group_name = data.azurerm_resource_group.rg.name
}
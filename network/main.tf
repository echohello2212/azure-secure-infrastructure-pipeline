#Create Azure Resource Group
resource "azurerm_resource_group" "rg_asip" {
  name     = var.resource_group_name
  location = var.location
}

#Create Azure VNet
resource "azurerm_virtual_network" "vnet_asip" {
  name          = var.vnet_name
  address_space = var.vnet_address_space
  #reference location and resource group from the resource group resource instead of as a variable
  location            = azurerm_resource_group.rg_asip.location
  resource_group_name = azurerm_resource_group.rg_asip.name
}

#Create Frontend Subnet
resource "azurerm_subnet" "frontend_subnet" {
  name                = "snet-frontend"
  resource_group_name = azurerm_resource_group.rg_asip.name
  #reference the vnet name from the virtual network resource instead of as a variable
  virtual_network_name = azurerm_virtual_network.vnet_asip.name
  address_prefixes     = [var.frontend_subnet_prefix]
  #No implicit internet access, a NAT gateway is needed for outbound traffic
  default_outbound_access_enabled = false
}

#Create Backend Subnet
#No implicit internet access, a NAT gateway AND explicit NSG rule are needed for outbound traffic
resource "azurerm_subnet" "backend_subnet" {
  name                            = "snet-backend"
  resource_group_name             = azurerm_resource_group.rg_asip.name
  virtual_network_name            = azurerm_virtual_network.vnet_asip.name
  address_prefixes                = [var.backend_subnet_prefix]
  default_outbound_access_enabled = false
}

#Create Bastion Host Subnet
resource "azurerm_subnet" "bastion_subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.rg_asip.name
  virtual_network_name = azurerm_virtual_network.vnet_asip.name
  address_prefixes     = [var.bastion_subnet_prefix]
}

#Create Application Gateway Subnet
resource "azurerm_subnet" "appgw_subnet" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.rg_asip.name
  virtual_network_name = azurerm_virtual_network.vnet_asip.name
  address_prefixes     = [var.appgw_subnet_prefix]
}

#Create Private Endpoint Subnet
resource "azurerm_subnet" "endpoints_subnet" {
  name                              = "snet-endpoints"
  resource_group_name               = azurerm_resource_group.rg_asip.name
  virtual_network_name              = azurerm_virtual_network.vnet_asip.name
  address_prefixes                  = [var.endpoints_subnet_prefix]
  private_endpoint_network_policies = "Enabled"
}

#Private DNS zone for blob storage, resolves the storage name to the private endpoint
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg_asip.name
}

#Links the blob zone to the VNet. No registration, the private endpoint creates the record
resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link_blob" {
  name                  = "vnet-link-blob"
  resource_group_name   = azurerm_resource_group.rg_asip.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.vnet_asip.id
  registration_enabled  = false
}
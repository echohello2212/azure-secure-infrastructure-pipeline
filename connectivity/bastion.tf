#Public IP for Bastion access. Standard SKU requires Static allocation
resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku                 = "Standard"
  allocation_method   = "Static"
}

#Bastion host for SSH to the VMs. Basic SKU since only portal access is needed
resource "azurerm_bastion_host" "bastion" {
  name                = "bas-asip"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku                 = "Basic"

  ip_configuration {
    name                 = "ipconfig-bastion"
    subnet_id            = data.azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}
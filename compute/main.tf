#Network names are written here instead of in variables to reduce clutter and keep the code simple
#Update them if the network stack is renamed
#Looks up the frontend subnet from the network stack, its ID is used by the VM network interface
data "azurerm_subnet" "frontend" {
  name                 = "snet-frontend"
  virtual_network_name = "vnet-asip"
  resource_group_name  = "rg-asip"
}

#Looks up the backend subnet from the network stack, its ID is used by the VM network interface
data "azurerm_subnet" "backend" {
  name                 = "snet-backend"
  virtual_network_name = "vnet-asip"
  resource_group_name  = "rg-asip"
}
#Looks up data associated with the resource group
data "azurerm_resource_group" "rg" {
  name = "rg-asip"
}

# Generate unique VM names and convert them to a set (toset) so for_each can use each VM name as a resource identifier.
locals {
  frontend_vms = toset([for i in range(var.frontend_vm_count) : "frontend-${i + 1}"])
  backend_vms  = toset([for i in range(var.backend_vm_count) : "backend-${i + 1}"])
}

#Frontend VM NIC Configuration
resource "azurerm_network_interface" "frontend" {
  for_each            = local.frontend_vms
  name                = "nic-${each.key}"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.frontend.id
    private_ip_address_allocation = "Dynamic"
  }
}

#Backend VM NIC Configuration
resource "azurerm_network_interface" "backend" {
  for_each            = local.backend_vms
  name                = "nic-${each.key}"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.backend.id
    private_ip_address_allocation = "Dynamic"
  }
}

#Frontend VMs, individual names from local.frontend_vms
resource "azurerm_linux_virtual_machine" "frontend" {
  for_each            = local.frontend_vms
  name                = each.key
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  size                = var.vm_size
  admin_username      = var.admin_username

  #Key login only
  disable_password_authentication = true

  #NIC same key as corresponding VM. No public IP
  network_interface_ids = [azurerm_network_interface.frontend[each.key].id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  #Ubuntu 24.04 LTS, version pinned for reproducibility (checked Oct 2026)
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "24.04.202610210"
  }
}

#Backend VMs, individual names from local.backend_vms
resource "azurerm_linux_virtual_machine" "backend" {
  for_each            = local.backend_vms
  name                = each.key
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  size                = var.vm_size
  admin_username      = var.admin_username

  #Key login only
  disable_password_authentication = true

  #NIC same key as corresponding VM. No public IP
  network_interface_ids = [azurerm_network_interface.backend[each.key].id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  #Ubuntu 24.04 LTS, version pinned for reproducibility (checked Oct 2026)
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "24.04.202610210"
  }
}
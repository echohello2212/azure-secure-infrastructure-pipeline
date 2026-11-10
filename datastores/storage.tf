#Long term data store. Hardened: no public access by default, no shared keys, no anonymous containers
resource "azurerm_storage_account" "sa_asip" {
  name                             = "asipbackendstorageacc11"
  resource_group_name              = data.azurerm_resource_group.rg_asip.name
  location                         = data.azurerm_resource_group.rg_asip.location
  account_tier                     = "Standard"
  account_replication_type         = "LRS"
  min_tls_version                  = "TLS1_2"
  public_network_access_enabled    = var.storage_public_access
  allow_nested_items_to_be_public  = false
  shared_access_key_enabled        = false
  cross_tenant_replication_enabled = false

  #Soft delete and versioning so deleted or overwritten data can be recovered
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  #Firewall for the public endpoint. Only the admin IP is allowed, and only when public access is switched on
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = [var.admin_ip]
  }

  #Remove prevent_destroy before destroying, this account holds data
  lifecycle {
    prevent_destroy = true
  }
}

#Private endpoint for blob storage in the endpoints subnet, registers its record in the blob DNS zone
resource "azurerm_private_endpoint" "pe_blob" {
  name                = "pe-blob"
  resource_group_name = data.azurerm_resource_group.rg_asip.name
  location            = data.azurerm_resource_group.rg_asip.location
  subnet_id           = data.azurerm_subnet.endpoints_subnet.id

  private_service_connection {
    name                           = "pe-blob-psc"
    private_connection_resource_id = azurerm_storage_account.sa_asip.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "pe-blob-dzg"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.blob.id]
  }
}
#Private container for backend documents, No public access
resource "azurerm_storage_container" "blob_asip" {
  name                  = "blob-asip"
  storage_account_id    = azurerm_storage_account.sa_asip.id
  container_access_type = "private"

  #Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
}
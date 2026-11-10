resource "azurerm_mssql_server" "sql_asip" {
  name                          = "sql-server-asip11223"
  location                      = data.azurerm_resource_group.rg_asip.location
  resource_group_name           = data.azurerm_resource_group.rg_asip.name
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

  azuread_administrator {
    login_username              = var.sql_admin_login
    object_id                   = data.azurerm_client_config.current.object_id
    azuread_authentication_only = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_mssql_database" "db_asip" {
  name                        = "db-asip"
  server_id                   = azurerm_mssql_server.sql_asip.id
  sku_name                    = "GP_S_Gen5_1"
  min_capacity                = 0.5
  auto_pause_delay_in_minutes = 30
  max_size_gb                 = 10
  storage_account_type        = "Local"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_private_endpoint" "pe_sql" {
  name                = "pe-sql"
  resource_group_name = data.azurerm_resource_group.rg_asip.name
  location            = data.azurerm_resource_group.rg_asip.location
  subnet_id           = data.azurerm_subnet.endpoints_subnet.id

  private_service_connection {
    name                           = "pe-sql-psc"
    private_connection_resource_id = azurerm_mssql_server.sql_asip.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }

  private_dns_zone_group {
    name                 = "pe-sql-dzg"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.db.id]
  }
}
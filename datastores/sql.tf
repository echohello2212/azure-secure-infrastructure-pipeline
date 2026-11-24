resource "azurerm_mssql_server" "sql_asip" {
  #checkov:skip=CKV_AZURE_23:sql demonstrates the data tier, not real data, auditing is a production option
  #checkov:skip=CKV_AZURE_24:audit retention is a production option, demonstration database only
  #checkov:skip=CKV2_AZURE_2:vulnerability assessment is a production option, demonstration database only
  name                          = "sql-server-asip11223"
  location                      = data.azurerm_resource_group.rg_asip.location
  resource_group_name           = data.azurerm_resource_group.rg_asip.name
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

  azuread_administrator {
    login_username              = var.sql_admin_login
    object_id                   = var.sql_admin_object_id
    azuread_authentication_only = true
  }

  #Protects the database server, removed by the teardown workflow or by hand for a local destroy
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_mssql_database" "db_asip" {
  #checkov:skip=CKV_AZURE_224:demonstration db, ledger not needed
  #checkov:skip=CKV_AZURE_229:zone redundancy costs more, demonstration serverless db with local storage
  name                        = "db-asip"
  server_id                   = azurerm_mssql_server.sql_asip.id
  sku_name                    = "GP_S_Gen5_1"
  min_capacity                = 0.5
  auto_pause_delay_in_minutes = 30
  max_size_gb                 = 10
  storage_account_type        = "Local"

  #Protects the database, removed by the teardown workflow or by hand for a local destroy
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
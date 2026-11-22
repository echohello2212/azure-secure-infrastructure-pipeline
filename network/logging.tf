#Log Analytics workspace for gateway logs. 30 days retention, 1 GB daily cap as a cost guard
resource "azurerm_log_analytics_workspace" "log_asip" {
  name                = "log-asip"
  location            = data.azurerm_resource_group.rg_asip.location
  resource_group_name = data.azurerm_resource_group.rg_asip.name
  sku                 = "PerGB2018"
  daily_quota_gb      = 1
  retention_in_days   = 30

  #Protects the audit trail, removed by the teardown workflow or by hand for a local destroy
  lifecycle {
    prevent_destroy = true
  }
}
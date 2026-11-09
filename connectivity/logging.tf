#Sends Application Gateway logs to workspace in dedicated tables
resource "azurerm_monitor_diagnostic_setting" "diag_appgw" {
  name                           = "diag-appgw"
  target_resource_id             = azurerm_application_gateway.appgw_asip.id
  log_analytics_workspace_id     = data.azurerm_log_analytics_workspace.log_asip.id
  log_analytics_destination_type = "Dedicated"

  #WAF log, shows rules matched and blocked
  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  #Access log, one entry per request. Shows source IP
  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }
}
#WAF policy for the application gateway
resource "azurerm_web_application_firewall_policy" "waf_appgw" {
  name                = "waf-appgw"
  location            = data.azurerm_resource_group.rg_asip.location
  resource_group_name = data.azurerm_resource_group.rg_asip.name

  #Detection logs matches without blocking, switched to Prevention after the first test
  policy_settings {
    enabled = true
    mode    = "Prevention"
  }

  #Latest OWASP version the provider supports, pinned, Azure does not upgrade it (checked Nov 2026)
  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"

    }
  }
}
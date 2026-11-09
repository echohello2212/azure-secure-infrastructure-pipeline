#Lookup existing Resource Group from Network Root
data "azurerm_resource_group" "rg" {
  name = "rg-asip"
}

#Lookup Application Gateway Public IP from Connectivity Root
data "azurerm_public_ip" "pip_appgw" {
  name                = "pip-appgw"
  resource_group_name = data.azurerm_resource_group.rg.name
}

#Front Door profile, Standard tier. Custom WAF rules only, managed rules stay on the gateway
resource "azurerm_cdn_frontdoor_profile" "afd_asip" {
  name                = "afd-asip"
  resource_group_name = data.azurerm_resource_group.rg.name
  sku_name            = "Standard_AzureFrontDoor"
}

#Edge WAF policy, coarse filtering before traffic reaches the gateway
resource "azurerm_cdn_frontdoor_firewall_policy" "waf_frontdoor" {
  name                              = "wafFrontDoor"
  resource_group_name               = data.azurerm_resource_group.rg.name
  sku_name                          = azurerm_cdn_frontdoor_profile.afd_asip.sku_name
  enabled                           = true
  mode                              = "Prevention"
  custom_block_response_status_code = 403

  #Priorities: 100s match rules, 200s rate limit rules, steps of 10
  #Allow only GET and HEAD, block every other method
  custom_rule {
    name     = "AllowOnlyGetHead"
    enabled  = true
    priority = 100
    type     = "MatchRule"
    action   = "Block"

    match_condition {
      match_variable     = "RequestMethod"
      operator           = "Equal"
      negation_condition = true
      match_values       = ["GET", "HEAD"]
    }
  }

  #Max 20 requests per minute. Counted per client IP
  custom_rule {
    name                           = "RateLimitPerClientIP"
    enabled                        = true
    priority                       = 200
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 20
    type                           = "RateLimitRule"
    action                         = "Block"

    #Includes all URIs
    match_condition {
      match_variable     = "RequestUri"
      operator           = "Contains"
      negation_condition = false
      match_values       = ["/"]
    }
  }
}

#Front Door security policy, attaches the WAF policy to the endpoint
resource "azurerm_cdn_frontdoor_security_policy" "sp_frontdoor" {
  name                     = "sp-frontdoor"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd_asip.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.waf_frontdoor.id
      association {
        patterns_to_match = ["/*"]
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.ep_asip.id
        }
      }
    }
  }
}

#Front Door endpoint, the public hostname for the site
resource "azurerm_cdn_frontdoor_endpoint" "ep_asip" {
  name                     = "ep-asip"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd_asip.id
}

#Origin group, groups the origins and sets the health probe
resource "azurerm_cdn_frontdoor_origin_group" "og_asip" {
  name                     = "og-asip"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd_asip.id
  load_balancing {

  }
  health_probe {
    protocol            = "Http"
    path                = "/"
    interval_in_seconds = 100
    request_type        = "HEAD"
  }
}

#Origin, the application gateway public IP. Plain HTTP because the gateway has no HTTPS listener
resource "azurerm_cdn_frontdoor_origin" "origin_appgw" {
  name                           = "origin-appgw"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.og_asip.id
  enabled                        = true
  host_name                      = data.azurerm_public_ip.pip_appgw.ip_address
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = data.azurerm_public_ip.pip_appgw.ip_address
  certificate_name_check_enabled = false
}

#Route, sends all paths from the endpoint to the origin group over HTTP. Clients are redirected to HTTPS at the edge
resource "azurerm_cdn_frontdoor_route" "route_asip" {
  name                          = "route-asip"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.ep_asip.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.og_asip.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.origin_appgw.id]
  forwarding_protocol           = "HttpOnly"
  supported_protocols           = ["Http", "Https"]
  patterns_to_match             = ["/*"]
  https_redirect_enabled        = true
  link_to_default_domain        = true
}

#Front Door endpoint hostname, used for testing
output "frontdoor_hostname" {
  value = azurerm_cdn_frontdoor_endpoint.ep_asip.host_name
}
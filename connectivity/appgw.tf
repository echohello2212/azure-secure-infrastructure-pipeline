#Names defined for use in several blocks in the application gateway
locals {
  appgw_ip_config          = "appgw-ip-config"
  appgw_ip_config_frontend = "appgw-ip-config-frontend"
  appgw_frontend_port      = "appgw-port-80"
  appgw_backend_pool       = "appgw-backend-pool"
  appgw_backend_settings   = "appgw-backend-settings"
  appgw_probe              = "appgw-probe"
  appgw_listener           = "appgw-listener"
  appgw_routing_rule       = "appgw-routing-rule"
}

#Public IP for the application gateway, Standard SKU. Static allocation required
resource "azurerm_public_ip" "pip_appgw" {
  name                = "pip-appgw"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku                 = "Standard"
  allocation_method   = "Static"
}

#Application gateway with WAF, receives HTTP and forwards to the frontend VM
#Policy ID attaches the WAF policy defined in waf.tf
resource "azurerm_application_gateway" "appgw_asip" {
  name                = "appgw-asip"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  firewall_policy_id  = azurerm_web_application_firewall_policy.waf_appgw.id

  #Fixed capacity of 1 to keep costs low, autoscaling would replace it in production
  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  #Subnet the gateway itself lives in
  gateway_ip_configuration {
    name      = local.appgw_ip_config
    subnet_id = data.azurerm_subnet.appgw.id
  }

  #Port the gateway listens on
  frontend_port {
    name = local.appgw_frontend_port
    port = 80
  }

  #Public IP clients connect to
  frontend_ip_configuration {
    name                 = local.appgw_ip_config_frontend
    public_ip_address_id = azurerm_public_ip.pip_appgw.id
  }

  #Frontend VM private IP, traffic is forwarded here
  backend_address_pool {
    name         = local.appgw_backend_pool
    ip_addresses = [data.azurerm_network_interface.nic_frontend_1.private_ip_address]
  }

  #How the gateway talks to the backend HTTP port 80
  backend_http_settings {
    name                  = local.appgw_backend_settings
    port                  = 80
    protocol              = "Http"
    cookie_based_affinity = "Disabled"
    request_timeout       = 30
    probe_name            = local.appgw_probe
  }

  #Health check, the gateway only sends traffic to a backend that returns 200-399
  #Single site setup, 127.0.0.1 is the default probe host
  probe {
    name                = local.appgw_probe
    protocol            = "Http"
    path                = "/"
    interval            = 10
    timeout             = 10
    unhealthy_threshold = 3
    host                = "127.0.0.1"
    match {
      status_code = ["200-399"]
    }
  }

  #Accepts incoming HTTP requests on the public frontend
  http_listener {
    name                           = local.appgw_listener
    frontend_port_name             = local.appgw_frontend_port
    frontend_ip_configuration_name = local.appgw_ip_config_frontend
    protocol                       = "Http"
  }

  #Connects the listener to the backend pool and settings
  request_routing_rule {
    name                       = local.appgw_routing_rule
    http_listener_name         = local.appgw_listener
    backend_http_settings_name = local.appgw_backend_settings
    backend_address_pool_name  = local.appgw_backend_pool
    rule_type                  = "Basic"
    priority                   = 100
  }
}
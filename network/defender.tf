#Resource types whose Defender plan is pinned to Free
locals {
  defender_types = toset([
    "CloudPosture",
    "VirtualMachines",
    "SqlServers",
    "StorageAccounts",
  ])
}

#Pins Defender plans to Free so no paid plan can bill
resource "azurerm_security_center_subscription_pricing" "defender" {
  for_each      = local.defender_types
  tier          = "Free"
  resource_type = each.value

}
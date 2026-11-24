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
  #checkov:skip=CKV_AZURE_19:free tier on purpose for the lab, paid plans are a production option
  #checkov:skip=CKV_AZURE_55:defender for servers left free for the lab
  #checkov:skip=CKV_AZURE_69:defender for sql left free for the lab
  #checkov:skip=CKV_AZURE_84:defender for storage left free for the lab
  for_each      = local.defender_types
  tier          = "Free"
  resource_type = each.value

}
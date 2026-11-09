terraform {
  backend "azurerm" {
    resource_group_name  = "rg-asip-tfstate"
    storage_account_name = "asiptfstate86089"
    container_name       = "tfstate"
    key                  = "datastores.tfstate"
    use_azuread_auth     = true
  }
}
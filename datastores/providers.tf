#Terraform and provider requirements
terraform {
  #Terraform minimum version
  required_version = ">= 1.16.5"

  required_providers {
    ## AzureRM provider version constraint (>= 4.0, < 5.0)
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
#Azure RM provider configuration
#Subscription ID for authentication set as variable for replication and security purposes
#Storage access uses Entra ID instead of shared keys
provider "azurerm" {
  features {}

  subscription_id     = var.subscription_id
  storage_use_azuread = true
}
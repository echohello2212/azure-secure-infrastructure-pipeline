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
provider "azurerm" {
  #Subscription ID for authentication set as variable for replication and security purposes
  features {}
  resource_provider_registrations = "none"
  subscription_id                 = var.subscription_id
}
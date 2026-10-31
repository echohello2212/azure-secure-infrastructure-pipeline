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
#Azure RM provider configu
provider "azurerm" {
  features {}
  #Subscription ID for authentication set as variable for replication and security purposes
  subscription_id = var.subscription_id
}
#Terraform and provider requirements
terraform {
  required_version = ">= 1.8.0"

  required_providers {
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
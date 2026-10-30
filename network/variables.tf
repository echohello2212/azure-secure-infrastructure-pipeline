#Resource Group location
variable "location" {
  description = "The Azure region where the resources will be created."
  type        = string
}

#Resource Group name
variable "resource_group_name" {
  description = "The name of the resource group to create."
  type        = string
  default     = "rg-asip"
}

#Virtual Network name
variable "vnet_name" {
  description = "The name of the virtual network to create."
  type        = string
  default     = "vnet-asip"
}

#Virtual Network Address Space config
variable "vnet_address_space" {
  description = "The address space for the virtual network."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

#Frontend Subnet config
variable "frontend_subnet_prefix" {
  description = "The prefix for the frontend subnet."
  type        = string
  default     = "10.0.1.0/24"
}

#Backend Subnet config
variable "backend_subnet_prefix" {
  description = "The prefix for the backend subnet."
  type        = string
  default     = "10.0.2.0/24"
}

#Bastion Subnet config
variable "bastion_subnet_prefix" {
  description = "The prefix for the bastion subnet."
  type        = string
  default     = "10.0.3.0/24"
}

#Application Gateway Subnet config
variable "appgw_subnet_prefix" {
  description = "The prefix for the application gateway subnet."
  type        = string
  default     = "10.0.4.0/24"
}

#Subscription ID. saved as env variable for replication and security purposes.
variable "subscription_id" {
  description = "The Azure subscription ID (GUID)."
  type        = string
  #Validation to ensure the subscription_id is a valid GUID format
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a valid GUID."
  }
}

#Admin IP entered as string for practical purposes of this lab
variable "admin_ip" {
  description = "The current public IP address of the admin workstation."
  type        = string
}
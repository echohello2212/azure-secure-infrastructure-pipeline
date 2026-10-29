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

#Management Subnet config
variable "management_subnet_prefix" {
  description = "The prefix for the management subnet."
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
}
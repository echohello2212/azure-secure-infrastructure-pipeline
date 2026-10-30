#Resource Group location
variable "location" {
  description = "The Azure region where the resources will be created."
  type        = string
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


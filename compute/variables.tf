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

#Availability differs per region and subscription. Check with az vm list-SKUs before changing
variable "vm_size" {
  description = "The size of the virtual machine."
  type        = string
  #Check available SKUs first
  default = "Standard_B2ts_v2"
}

variable "admin_username" {
  description = "The admin username for the virtual machine."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "The path to the SSH public key for the virtual machine."
  type        = string
}

variable "frontend_vm_count" {
  description = "The number of frontend virtual machines to create. Horizontal scalability."
  type        = number
  default     = 1

  validation {
    condition     = var.frontend_vm_count >= 0
    error_message = "frontend_vm_count must be 0 or higher."
  }
}


variable "backend_vm_count" {
  description = "The number of backend virtual machines to create. Horizontal scalability."
  type        = number
  default     = 1

  validation {
    condition     = var.backend_vm_count >= 0
    error_message = "backend_vm_count must be 0 or higher."
  }
}




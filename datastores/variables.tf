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
  #Validation accepts only plain IPv4 address and rejects CIDR notation etc
  validation {
    condition     = can(regex("^((25[0-5]|(2[0-4]|1\\d|[1-9]|)\\d)\\.?\\b){4}$", var.admin_ip))
    error_message = "admin_ip must be a valid IPv4 address."
  }
}

variable "storage_public_access" {
  description = "Temporarily opens storage account's public endpoint. Limited to admin IP, keep false otherwise."
  type        = bool
  default     = false
}

variable "sql_admin_login" {
  description = "The Azure AD login name of the SQL admin user."
  type        = string
  sensitive   = true
}

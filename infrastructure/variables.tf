variable "resource_group_location" {
  type        = string
  default     = "eastus"
  description = "Location of the resource group."
}

variable "username" {
  type        = string
  description = "The username for the local account that will be created on the new VM."
  default     = "azureadmin"
}

variable "api_token" {
  description = "API token for DNS provider or HPC cloud integration"
  type        = string
  default     = null
  sensitive   = true
}

variable "zone_id" {
  description = "The zone ID for the DNS provider"
  type        = string
  default     = null
  sensitive   = true
}

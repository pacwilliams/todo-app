variable "resource_group_location" {
  type        = string
  default     = "eastus"
  description = "Location of the resource group."
}

variable "resource_group_name_prefix" {
  type        = string
  default     = "ODL-candidate-sandbox-02-1986716"
  description = "Prefix of the resource group name that's combined with a random ID so name is unique in your Azure subscription."
}

variable "username" {
  type        = string
  description = "The username for the local account that will be created on the new VM."
  default     = "azureadmin"
}

variable "enable_manifests" {
  type        = bool
  description = "Enable or disable the deployment of Kubernetes manifests."
  default     = true
}

variable "api_token" {
  description = "API token for DNS provider or HPC cloud integration"
  type        = string
  default = null
  sensitive   = true
}

variable "zone_id" {
  description = "The zone ID for the DNS provider"
  type        = string
  default = null
  sensitive = true
}
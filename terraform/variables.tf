variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "uksouth"
}

variable "cluster_name" {
  description = "ARO HCP cluster name (also used for identity naming)."
  type        = string
}

variable "resource_group_name" {
  description = "Customer resource group name."
  type        = string
}

variable "vnet_name" {
  description = "Virtual network name."
  type        = string
  default     = "customer-vnet"
}

variable "subnet_name" {
  description = "Worker subnet name."
  type        = string
  default     = "customer-subnet-1"
}

variable "vnet_integration_subnet_name" {
  description = "VNet integration subnet name."
  type        = string
  default     = "customer-vnet-integration-subnet"
}

variable "nsg_name" {
  description = "Network security group name."
  type        = string
  default     = "customer-nsg"
}

variable "address_prefix" {
  description = "VNet address prefix."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_prefix" {
  description = "Worker subnet address prefix."
  type        = string
  default     = "10.0.0.0/24"
}

variable "vnet_integration_subnet_prefix" {
  description = "VNet integration subnet address prefix."
  type        = string
  default     = "10.0.1.0/24"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

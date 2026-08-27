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

variable "managed_resource_group_name" {
  description = "Managed resource group created by the ARO HCP resource provider. Defaults to <cluster_name>-managed."
  type        = string
  default     = null
  nullable    = true
}

variable "cluster_version" {
  description = "OpenShift version for the HCP cluster (X.Y)."
  type        = string
  default     = "4.22"
}

variable "cluster_channel" {
  description = "OpenShift channel group for the cluster."
  type        = string
  default     = "stable"
}

variable "api_visibility" {
  description = "Kube-apiserver visibility: Public or Private. Create-time only."
  type        = string
  default     = "Public"

  validation {
    condition     = contains(["Public", "Private"], var.api_visibility)
    error_message = "api_visibility must be Public or Private."
  }
}

variable "outbound_type" {
  description = "Cluster egress: LoadBalancer or UserDefinedRouting."
  type        = string
  default     = "LoadBalancer"

  validation {
    condition     = contains(["LoadBalancer", "UserDefinedRouting"], var.outbound_type)
    error_message = "outbound_type must be LoadBalancer or UserDefinedRouting."
  }
}

variable "cluster_image_registry_state" {
  description = "Cluster image registry state: Enabled or Disabled."
  type        = string
  default     = "Enabled"

  validation {
    condition     = contains(["Enabled", "Disabled"], var.cluster_image_registry_state)
    error_message = "cluster_image_registry_state must be Enabled or Disabled."
  }
}

variable "vault_visibility" {
  description = "etcd KMS Key Vault visibility: Public or Private."
  type        = string
  default     = "Public"

  validation {
    condition     = contains(["Public", "Private"], var.vault_visibility)
    error_message = "vault_visibility must be Public or Private."
  }
}

variable "pod_cidr" {
  description = "Kubernetes pod CIDR. Must not overlap the VNet or service CIDR."
  type        = string
  default     = "10.128.0.0/14"
}

variable "service_cidr" {
  description = "Kubernetes service CIDR. Must not overlap the VNet or pod CIDR."
  type        = string
  default     = "172.30.0.0/16"
}

variable "host_prefix" {
  description = "Host prefix for the cluster network."
  type        = number
  default     = 23
}

variable "node_pool_name" {
  description = "Name of the default HCP node pool."
  type        = string
  default     = "np-1"
}

variable "node_pool_vm_size" {
  description = "Azure VM size for the default node pool."
  type        = string
  default     = "Standard_D4s_v6"
}

variable "node_pool_disk_size_gib" {
  description = "OS disk size in GiB for the default node pool."
  type        = number
  default     = 64
}

variable "node_pool_disk_storage_account_type" {
  description = "OS disk storage account type for the default node pool."
  type        = string
  default     = "StandardSSD_LRS"
}

variable "node_pool_replicas" {
  description = "Replica count for the default node pool. Cluster Service requires at least 2."
  type        = number
  default     = 2

  validation {
    condition     = var.node_pool_replicas >= 2
    error_message = "node_pool_replicas must be at least 2."
  }
}

variable "node_pool_version" {
  description = "OpenShift version for the default node pool (X.Y.Z)."
  type        = string
  default     = "4.22.9"
}

variable "node_pool_channel" {
  description = "OpenShift channel group for the default node pool."
  type        = string
  default     = "stable"
}

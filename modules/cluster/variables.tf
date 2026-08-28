variable "cluster_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "resource_group_id" {
  type = string
}

variable "location" {
  type = string
}

variable "managed_resource_group_name" {
  type     = string
  default  = null
  nullable = true
}

variable "address_prefix" {
  type = string
}

variable "worker_subnet_id" {
  type = string
}

variable "vnet_integration_subnet_id" {
  type = string
}

variable "nsg_id" {
  type = string
}

variable "key_vault_name" {
  type = string
}

variable "etcd_key_version" {
  type = string
}

variable "etcd_encryption_key_name" {
  type = string
}

variable "service_identity_id" {
  type = string
}

variable "control_plane_operators" {
  type = map(string)
}

variable "data_plane_operators" {
  type = map(string)
}

variable "cluster_identity_ids" {
  type = set(string)
}

variable "cluster_version" {
  type    = string
  default = "4.22"
}

variable "cluster_channel" {
  type    = string
  default = "stable"
}

variable "api_visibility" {
  type    = string
  default = "Public"
}

variable "ingress_visibility" {
  type    = string
  default = "Public"
}

variable "outbound_type" {
  type    = string
  default = "LoadBalancer"
}

variable "cluster_image_registry_state" {
  type    = string
  default = "Enabled"
}

variable "vault_visibility" {
  type    = string
  default = "Public"
}

variable "pod_cidr" {
  type    = string
  default = "10.128.0.0/14"
}

variable "service_cidr" {
  type    = string
  default = "172.30.0.0/16"
}

variable "host_prefix" {
  type    = number
  default = 23
}

variable "node_pool_name" {
  type    = string
  default = "np-1"
}

variable "node_pool_vm_size" {
  type    = string
  default = "Standard_D4s_v6"
}

variable "node_pool_disk_size_gib" {
  type    = number
  default = 64
}

variable "node_pool_disk_storage_account_type" {
  type    = string
  default = "StandardSSD_LRS"
}

variable "node_pool_replicas" {
  type    = number
  default = 2
}

variable "node_pool_version" {
  type    = string
  default = "4.22.9"
}

variable "node_pool_channel" {
  type    = string
  default = "stable"
}

variable "tags" {
  type    = map(string)
  default = {}
}

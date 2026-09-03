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

variable "node_pool_version" {
  description = "OpenShift version (X.Y.Z) inherited by node_pools entries that omit version."
  type        = string
  default     = "4.22.9"
}

variable "node_pool_channel" {
  description = "OpenShift channel group inherited by node_pools entries that omit channel."
  type        = string
  default     = "stable"
}

variable "node_pools" {
  description = <<-EOT
    HCP nodePools children keyed by ARM name. At least one pool is required (ARO does not create a default).
    Fields match az aro hcp cluster nodepool create. Optional CLI flags (subnet_id, disk_*, auto_repair,
    encryption_at_host, node_drain_timeout, labels, taints) are omitted from ARM when unset.
    availability_zone is an Azure zone number (1, 2, or 3); omit to leave the pool unpinned.
    Set min_replicas and max_replicas together for autoscaling (replicas is omitted from ARM).
  EOT
  type = map(object({
    vm_size                   = string
    replicas                  = optional(number, 2)
    min_replicas              = optional(number)
    max_replicas              = optional(number)
    version                   = optional(string)
    channel                   = optional(string)
    disk_size_gib             = optional(number)
    disk_storage_account_type = optional(string)
    disk_type                 = optional(string)
    disk_encryption_set       = optional(string)
    availability_zone         = optional(string)
    encryption_at_host        = optional(bool)
    subnet_id                 = optional(string)
    auto_repair               = optional(bool)
    node_drain_timeout        = optional(number)
    labels                    = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    tags = optional(map(string), {})
  }))
  default = {
    np-1 = {
      vm_size           = "Standard_D4s_v6"
      replicas          = 2
      availability_zone = "1"
    }
  }

  validation {
    condition     = length(var.node_pools) >= 1
    error_message = "node_pools must contain at least one pool."
  }

  validation {
    condition = alltrue([
      for p in var.node_pools :
      (p.min_replicas == null && p.max_replicas == null && p.replicas >= 2) ||
      (p.min_replicas != null && p.max_replicas != null && p.min_replicas >= 2 && p.max_replicas >= p.min_replicas)
    ])
    error_message = "Each pool must set replicas >= 2, or both min_replicas and max_replicas (min >= 2, max >= min). Do not set only one autoscaling bound."
  }

  validation {
    condition = alltrue([
      for p in var.node_pools :
      p.availability_zone == null || contains(["1", "2", "3"], p.availability_zone)
    ])
    error_message = "availability_zone must be omitted (unpinned) or Azure zone number 1, 2, or 3 — not a Kubernetes topology name like uksouth-1."
  }

  validation {
    condition = alltrue(flatten([
      for p in var.node_pools : [
        for t in p.taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)
      ]
    ]))
    error_message = "Each taint effect must be NoSchedule, PreferNoSchedule, or NoExecute."
  }

  validation {
    condition = alltrue([
      for p in var.node_pools : p.disk_type == null || contains(["Managed", "Ephemeral"], p.disk_type)
    ])
    error_message = "disk_type must be omitted, Managed, or Ephemeral."
  }

  validation {
    condition = alltrue([
      for p in var.node_pools : p.disk_storage_account_type == null || contains(["Premium_LRS", "StandardSSD_LRS", "Standard_LRS"], p.disk_storage_account_type)
    ])
    error_message = "disk_storage_account_type must be omitted, Premium_LRS, StandardSSD_LRS, or Standard_LRS."
  }

  validation {
    condition = alltrue([
      for p in var.node_pools :
      p.node_drain_timeout == null || (p.node_drain_timeout >= 0 && p.node_drain_timeout <= 10080)
    ])
    error_message = "node_drain_timeout must be 0–10080 minutes (CLI --node-drain-timeout)."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

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
  description = "Customer resource group name. Defaults to <cluster_name>-rg."
  type        = string
  default     = null
  nullable    = true
}

variable "vnet_name" {
  description = "Virtual network name. Defaults to <cluster_name>-vnet."
  type        = string
  default     = null
  nullable    = true
}

variable "subnet_name" {
  description = "Worker subnet name. Defaults to <cluster_name>-worker."
  type        = string
  default     = null
  nullable    = true
}

variable "vnet_integration_subnet_name" {
  description = "VNet integration subnet name. Defaults to <cluster_name>-integration."
  type        = string
  default     = null
  nullable    = true
}

variable "nsg_name" {
  description = "Network security group name. Defaults to <cluster_name>-nsg."
  type        = string
  default     = null
  nullable    = true
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

variable "jump_subnet_prefix" {
  description = "Dedicated jump box subnet prefix."
  type        = string
  default     = "10.0.2.0/28"
}

variable "netapp_subnet_prefix" {
  description = "Reserved CIDR for a sibling Azure NetApp Files delegated subnet (not created here). Default 10.0.3.0/24; must not overlap worker, integration, or jump."
  type        = string
  default     = "10.0.3.0/24"
}

variable "enable_jumpbox" {
  description = "Create a Fedora jump VM with a public IP for sshuttle."
  type        = bool
  default     = false
}

variable "jump_ssh_source_prefix" {
  description = "CIDR allowed to SSH to the jump VM. Required when enable_jumpbox is true."
  type        = string
  default     = ""
}

variable "jump_ssh_public_key" {
  description = "OpenSSH public key for the jump VM. Required when enable_jumpbox is true. Private key stays on the laptop."
  type        = string
  default     = ""
}

variable "jump_ssh_private_key_path" {
  description = "Path to the jump SSH private key on the operator machine (used in sshuttle command output)."
  type        = string
  default     = "clusters/default/jump"
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

variable "ingress_visibility" {
  description = "Default OpenShift ingress (console / *.apps) visibility: Public, Private, or Disabled. Create-time only."
  type        = string
  default     = "Public"

  validation {
    condition     = contains(["Public", "Private", "Disabled"], var.ingress_visibility)
    error_message = "ingress_visibility must be Public, Private, or Disabled."
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
    HCP nodePools children keyed by ARM name. Default is np-1 (D4s_v6 × 2, Azure zone 1).
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

variable "pull_secret_path" {
  description = "Path to a Red Hat dockerconfigjson pull secret. When set, Terraform writes it to the customer Key Vault as pull_secret_key_vault_secret_name. When empty, Terraform does not create or update that secret (bootstrap still reads it from Key Vault if present). Prefer an absolute path; relative paths are resolved from terraform/."
  type        = string
  default     = ""

  validation {
    condition     = trimspace(var.pull_secret_path) == "" || fileexists(var.pull_secret_path)
    error_message = "pull_secret_path must be an existing file or empty."
  }
}

variable "pull_secret_key_vault_secret_name" {
  description = "Key Vault secret name for the Red Hat pull secret."
  type        = string
  default     = "redhat-pull-secret"

  validation {
    condition     = can(regex("^[0-9a-zA-Z-]{1,127}$", var.pull_secret_key_vault_secret_name))
    error_message = "pull_secret_key_vault_secret_name must be 1-127 alphanumeric characters or hyphens."
  }
}

variable "enable_external_auth" {
  description = "Create the Entra OIDC app, Key Vault client secret, and HCP externalAuths child. Console secret and cluster-admin CRBs still need make cluster.<name>.external-auth after kubeconfig."
  type        = bool
  default     = true
}

variable "oidc_web_redirects" {
  description = <<-EOT
    Extra Entra Web redirect URIs (host + path) joined to apps.aro.<dns>.
    Console, GitOps, and PKCE http://localhost are always registered.
    Default includes RHOAI rh-ai /oauth2/callback. Set {} for none.
  EOT
  type = map(object({
    host = string
    path = string
  }))
  default = {
    rhoai = {
      host = "rh-ai"
      path = "/oauth2/callback"
    }
  }
}

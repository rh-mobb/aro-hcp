output "cluster_name" {
  value = var.cluster_name
}

output "resource_group_name" {
  value = module.network.resource_group_name
}

output "location" {
  value = module.network.location
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "subnet_id" {
  value = module.network.worker_subnet_id
}

output "vnet_integration_subnet_id" {
  value = module.network.vnet_integration_subnet_id
}

output "nsg_id" {
  value = module.network.nsg_id
}

output "vnet_id" {
  value = module.network.vnet_id
}

output "key_vault_name" {
  value = module.identities.key_vault_name
}

output "key_vault_id" {
  value = module.identities.key_vault_id
}

output "key_vault_uri" {
  value = module.identities.key_vault_uri
}

output "tenant_id" {
  value = module.identities.tenant_id
}

output "eso_identity_id" {
  description = "Resource ID of the ESO workload identity (not an HCP cluster identity)."
  value       = module.identities.eso_identity_id
}

output "eso_client_id" {
  description = "Client ID published to openshift-gitops/aro-platform-metadata for the GitOps annotation Job."
  value       = module.identities.eso_client_id
}

output "oidc_issuer_url" {
  description = "Cluster OIDC issuer used by the ESO federated identity credential."
  value       = module.cluster.oidc_issuer_url
}

output "etcd_key_version" {
  value = module.identities.etcd_key_version
}

output "pull_secret_key_vault_secret_name" {
  description = "Key Vault secret name for the Red Hat pull secret. Bootstrap reads this secret; the value is never exported."
  value       = module.identities.pull_secret_key_vault_secret_name
}

output "identity_ids" {
  description = "User-assigned identity resource IDs keyed by operator name."
  value       = module.identities.identity_ids
}

output "role_assignment_count" {
  value = module.identities.role_assignment_count
}

output "role_assignment_specs" {
  description = "Expected role assignment specs for testing."
  value       = module.identities.role_assignment_specs
}

output "cluster_id" {
  description = "Azure resource ID of the HCP cluster."
  value       = module.cluster.cluster_id
}

output "node_pool_ids" {
  description = "Azure resource IDs of HCP nodePools keyed by pool name."
  value       = module.cluster.node_pool_ids
}

output "node_pool_id" {
  description = "Azure resource ID of np-1 when present; otherwise the first pool."
  value       = module.cluster.node_pool_id
}

output "managed_resource_group_name" {
  description = "Managed resource group name for the HCP cluster."
  value       = module.cluster.managed_resource_group_name
}

output "api_url" {
  description = "Kubernetes API URL when reported by the HCP API."
  value       = module.cluster.api_url
}

output "console_url" {
  description = "OpenShift console URL when reported by the HCP API."
  value       = module.cluster.console_url
}

output "dns_base_domain" {
  description = "Service-assigned HCP DNS zone (properties.dns.baseDomain)."
  value       = module.cluster.dns_base_domain
}

output "dns_base_domain_prefix" {
  description = "DNS label for the cluster (properties.dns.baseDomainPrefix)."
  value       = module.cluster.dns_base_domain_prefix
}

output "entra_client_id" {
  description = "Entra application (client) ID when enable_external_auth is true."
  value       = var.enable_external_auth ? module.entra[0].client_id : null
}

output "entra_issuer_url" {
  description = "OIDC issuer URL when enable_external_auth is true."
  value       = var.enable_external_auth ? module.entra[0].issuer_url : null
}

output "entra_client_secret_name" {
  description = "Key Vault secret name for the Entra confidential client secret. Value is never exported."
  value       = var.enable_external_auth ? module.entra[0].client_secret_key_vault_secret_name : null
}

output "entra_web_redirect_uris" {
  description = "Web redirect URIs Terraform registers on the Entra app."
  value       = var.enable_external_auth ? module.entra[0].web_redirect_uris : []
}

output "cluster_version" {
  value = var.cluster_version
}

output "cluster_channel" {
  value = var.cluster_channel
}

output "node_pool_name" {
  description = "Convenience: np-1 if present, else the lexicographically first node_pools key."
  value       = contains(keys(var.node_pools), "np-1") ? "np-1" : sort(keys(var.node_pools))[0]
}

output "node_pool_version" {
  value = var.node_pool_version
}

output "node_pool_channel" {
  value = var.node_pool_channel
}

output "node_pools" {
  description = "Configured node pools (CLI-parity fields plus inherited version/channel)."
  value = {
    for name, p in var.node_pools : name => {
      vm_size           = p.vm_size
      replicas          = p.min_replicas != null ? null : p.replicas
      min_replicas      = p.min_replicas
      max_replicas      = p.max_replicas
      version           = coalesce(p.version, var.node_pool_version)
      channel           = coalesce(p.channel, var.node_pool_channel)
      availability_zone = p.availability_zone
      subnet_id         = p.subnet_id
      labels            = p.labels
      taints            = p.taints
    }
  }
}

output "api_visibility" {
  value = var.api_visibility
}

output "ingress_visibility" {
  value = var.ingress_visibility
}

output "jump_public_ip" {
  value = var.enable_jumpbox ? module.jumpbox[0].public_ip : null
}

output "jump_ssh_user" {
  value = var.enable_jumpbox ? module.jumpbox[0].ssh_user : null
}

output "jump_sshuttle_command" {
  value = var.enable_jumpbox ? module.jumpbox[0].sshuttle_command : null
}

output "vnet_name" {
  value = module.network.vnet_name
}

output "worker_subnet_name" {
  value = module.network.worker_subnet_name
}

output "worker_subnet_prefix" {
  value = module.network.worker_subnet_prefix
}

output "address_prefix" {
  value = module.network.address_prefix
}

output "jump_subnet_prefix" {
  description = "Jump subnet CIDR from tfvars (reserved even when enable_jumpbox is false)."
  value       = var.jump_subnet_prefix
}

output "netapp_subnet_prefix" {
  description = "Reserved ANF delegated-subnet CIDR. Not created in this root; sibling module consumes it."
  value       = var.netapp_subnet_prefix
}

output "platform" {
  description = "Versioned contract for a sibling virt/storage stack (terraform output -json platform)."
  value = {
    contract_version    = 1
    subscription_id     = data.azurerm_client_config.current.subscription_id
    tenant_id           = module.identities.tenant_id
    location            = module.network.location
    cluster_name        = var.cluster_name
    cluster_id          = module.cluster.cluster_id
    resource_group_name = module.network.resource_group_name
    network = {
      vnet_id              = module.network.vnet_id
      vnet_name            = module.network.vnet_name
      address_prefix       = module.network.address_prefix
      worker_subnet_id     = module.network.worker_subnet_id
      worker_subnet_name   = module.network.worker_subnet_name
      worker_subnet_prefix = module.network.worker_subnet_prefix
      nsg_id               = module.network.nsg_id
      jump_subnet_prefix   = var.jump_subnet_prefix
      reserved = {
        netapp_subnet_prefix = var.netapp_subnet_prefix
      }
    }
    oidc_issuer_url   = module.cluster.oidc_issuer_url
    key_vault_id      = module.identities.key_vault_id
    key_vault_name    = module.identities.key_vault_name
    key_vault_uri     = module.identities.key_vault_uri
    eso_client_id     = module.identities.eso_client_id
    api_url           = module.cluster.api_url
    api_visibility    = var.api_visibility
    cluster_version   = var.cluster_version
    node_pool_version = var.node_pool_version
    node_pools = {
      for name, p in var.node_pools : name => {
        vm_size           = p.vm_size
        replicas          = p.min_replicas != null ? null : p.replicas
        min_replicas      = p.min_replicas
        max_replicas      = p.max_replicas
        version           = coalesce(p.version, var.node_pool_version)
        channel           = coalesce(p.channel, var.node_pool_channel)
        availability_zone = p.availability_zone
        subnet_id         = p.subnet_id
        labels            = p.labels
        taints            = p.taints
      }
    }
  }
}

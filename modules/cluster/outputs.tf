output "managed_resource_group_name" {
  value = local.managed_resource_group_name
}

output "cluster_id" {
  description = "Azure resource ID of the HCP cluster."
  value       = azapi_resource.hcp_cluster.id
}

output "node_pool_id" {
  description = "Azure resource ID of the default node pool."
  value       = azapi_resource.node_pool.id
}

output "api_url" {
  description = "Kubernetes API URL when reported by the HCP API."
  value       = try(azapi_resource.hcp_cluster.output.properties.api.url, null)
}

output "console_url" {
  description = "OpenShift console URL when reported by the HCP API."
  value       = try(azapi_resource.hcp_cluster.output.properties.console.url, null)
}

output "oidc_issuer_url" {
  description = "Cluster OIDC issuer used for workload-identity federated credentials."
  value       = try(azapi_resource.hcp_cluster.output.properties.platform.issuerUrl, null)
}

output "dns_base_domain" {
  description = "Service-assigned HCP DNS zone (properties.dns.baseDomain)."
  value       = try(azapi_resource.hcp_cluster.output.properties.dns.baseDomain, null)
}

output "dns_base_domain_prefix" {
  description = "DNS label for the cluster (properties.dns.baseDomainPrefix)."
  value       = try(azapi_resource.hcp_cluster.output.properties.dns.baseDomainPrefix, null)
}

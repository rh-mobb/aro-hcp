output "managed_resource_group_name" {
  value = local.managed_resource_group_name
}

output "cluster_id" {
  description = "Azure resource ID of the HCP cluster."
  value       = azapi_resource.hcp_cluster.id
}

output "node_pool_ids" {
  description = "Azure resource IDs of HCP nodePools keyed by pool name."
  value       = { for name, r in azapi_resource.node_pool : name => r.id }
}

output "node_pool_id" {
  description = "Azure resource ID of np-1 when present; otherwise the first pool (CLI convenience)."
  value       = azapi_resource.node_pool[contains(keys(azapi_resource.node_pool), "np-1") ? "np-1" : sort(keys(azapi_resource.node_pool))[0]].id
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

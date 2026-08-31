locals {
  tags = merge(var.tags, {
    project = "aro-hcp-reference"
  })

  hcp_api_version             = "2026-06-30-preview"
  managed_resource_group_name = coalesce(var.managed_resource_group_name, "${var.cluster_name}-managed")
}

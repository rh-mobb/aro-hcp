# Enabled HCP versions for var.location. Same ARM list as `make versions` (hack/versions).
data "azapi_resource_list" "hcp_versions" {
  type      = "Microsoft.RedHatOpenShift/locations/hcpOpenShiftVersions@${local.hcp_api_version}"
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.RedHatOpenShift/locations/${var.location}"
  response_export_values = {
    enabled = "value[?properties.enabled].{name: name, channelGroup: properties.channelGroup}"
  }
}

locals {
  hcp_enabled_versions = coalesce(try(data.azapi_resource_list.hcp_versions.output.enabled, null), [])

  hcp_cluster_versions = sort([
    for v in local.hcp_enabled_versions : v.name
    if try(v.channelGroup, "") == var.cluster_channel
  ])

  hcp_node_pool_versions = sort([
    for v in local.hcp_enabled_versions : v.name
    if try(v.channelGroup, "") == var.node_pool_channel
  ])

  hcp_node_pool_versions_for = {
    for name, p in local.node_pools : name => sort([
      for v in local.hcp_enabled_versions : v.name
      if try(v.channelGroup, "") == p.channel
    ])
  }

  hcp_cluster_streams = sort(distinct([
    for ver in local.hcp_cluster_versions : join(".", slice(split(".", ver), 0, 2))
    if length(split(".", ver)) >= 2
  ]))
}

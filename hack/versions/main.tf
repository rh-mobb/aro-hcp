data "azurerm_client_config" "current" {}

data "azapi_resource_list" "hcp_versions" {
  type      = "Microsoft.RedHatOpenShift/locations/hcpOpenShiftVersions@${var.api_version}"
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.RedHatOpenShift/locations/${var.location}"
  response_export_values = {
    enabled = "value[?properties.enabled].{name: name, channelGroup: properties.channelGroup}"
  }
}

locals {
  enabled = coalesce(try(data.azapi_resource_list.hcp_versions.output.enabled, null), [])

  channels = sort(distinct([
    for v in local.enabled : v.channelGroup
    if try(v.channelGroup, "") != ""
  ]))

  patches = {
    for ch in local.channels :
    ch => sort([
      for v in local.enabled : v.name
      if try(v.channelGroup, "") == ch
    ])
  }

  streams = {
    for ch, names in local.patches :
    ch => sort(distinct([
      for p in names : join(".", slice(split(".", p), 0, 2))
      if length(split(".", p)) >= 2
    ]))
  }
}

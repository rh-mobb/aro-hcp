locals {
  tags = merge(var.tags, {
    project = "aro-hcp-reference"
  })

  resource_group_name          = coalesce(var.resource_group_name, "${var.cluster_name}-rg")
  vnet_name                    = coalesce(var.vnet_name, "${var.cluster_name}-vnet")
  subnet_name                  = coalesce(var.subnet_name, "${var.cluster_name}-worker")
  vnet_integration_subnet_name = coalesce(var.vnet_integration_subnet_name, "${var.cluster_name}-integration")
  nsg_name                     = coalesce(var.nsg_name, "${var.cluster_name}-nsg")
}

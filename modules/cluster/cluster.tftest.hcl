mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      client_id       = "00000000-0000-0000-0000-000000000002"
      object_id       = "00000000-0000-0000-0000-000000000003"
      subscription_id = "00000000-0000-0000-0000-000000000004"
    }
  }
}
mock_provider "azapi" {
  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        enabled = [
          { name = "4.22.9", channelGroup = "stable" },
          { name = "4.22.10", channelGroup = "stable" },
        ]
      }
    }
  }
}

variables {
  cluster_name                = "test-cluster"
  resource_group_name         = "test-rg"
  resource_group_id           = "/subscriptions/sub/resourceGroups/test-rg"
  location                    = "uksouth"
  managed_resource_group_name = "test-cluster-managed"
  address_prefix              = "10.0.0.0/16"
  worker_subnet_id            = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/worker"
  vnet_integration_subnet_id  = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/integration"
  nsg_id                      = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/nsg"
  key_vault_name              = "cust-kv-test"
  etcd_key_version            = "abc123"
  etcd_encryption_key_name    = "etcd-data-kms-encryption-key"
  service_identity_id         = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/svc"
  control_plane_operators = {
    "cluster-api-azure" = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/capi"
  }
  data_plane_operators = {
    "disk-csi-driver" = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/dpdisk"
  }
  cluster_identity_ids = toset([
    "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/svc",
    "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/capi",
  ])
}

run "hcp_cluster_uses_preview_api" {
  command = plan

  assert {
    condition     = azapi_resource.hcp_cluster.type == "Microsoft.RedHatOpenShift/hcpOpenShiftClusters@2026-06-30-preview"
    error_message = "Cluster AzAPI type must be hcpOpenShiftClusters@2026-06-30-preview."
  }
}

run "hcp_cluster_disables_schema_validation" {
  command = plan

  assert {
    condition     = azapi_resource.hcp_cluster.schema_validation_enabled == false
    error_message = "Preview cluster AzAPI resource must set schema_validation_enabled = false."
  }
}

run "node_pool_is_cluster_child" {
  command = plan

  assert {
    condition     = azapi_resource.node_pool["np-1"].type == "Microsoft.RedHatOpenShift/hcpOpenShiftClusters/nodePools@2026-06-30-preview"
    error_message = "Node pool AzAPI type must be hcpOpenShiftClusters/nodePools@2026-06-30-preview."
  }

  assert {
    condition     = azapi_resource.node_pool["np-1"].schema_validation_enabled == false
    error_message = "Preview node pool AzAPI resource must set schema_validation_enabled = false."
  }

  assert {
    condition     = azapi_resource.node_pool["np-1"].name == "np-1"
    error_message = "Default node pool name must be the node_pools map key."
  }

  assert {
    condition     = length(azapi_resource.node_pool) == 1
    error_message = "Default node_pools must create exactly np-1."
  }

  assert {
    condition     = azapi_resource.node_pool["np-1"].body.properties.platform.availabilityZone == "1"
    error_message = "Default np-1 must pin workers to Azure availability zone 1."
  }

  assert {
    condition     = try(azapi_resource.node_pool["np-1"].body.properties.platform.subnetId, null) == null
    error_message = "Omitting subnet_id must leave platform.subnetId unset (nil); do not inject the worker subnet."
  }

  assert {
    condition     = try(azapi_resource.node_pool["np-1"].body.properties.autoRepair, null) == null
    error_message = "Omitting auto_repair must leave properties.autoRepair unset."
  }

  assert {
    condition     = try(azapi_resource.node_pool["np-1"].body.properties.platform.osDisk, null) == null
    error_message = "Omitting disk fields must leave platform.osDisk unset."
  }

  assert {
    condition     = try(azapi_resource.node_pool["np-1"].body.properties.platform.enableEncryptionAtHost, null) == null
    error_message = "Omitting encryption_at_host must leave platform.enableEncryptionAtHost unset."
  }
}

run "additional_node_pool_is_cluster_child_with_labels" {
  command = plan

  variables {
    node_pools = {
      np-1 = {
        vm_size           = "Standard_D4s_v6"
        replicas          = 2
        availability_zone = "1"
      }
      np-virt = {
        vm_size           = "Standard_D8s_v6"
        replicas          = 2
        availability_zone = "1"
        labels = {
          workload = "virtualization"
        }
      }
    }
  }

  assert {
    condition     = length(azapi_resource.node_pool) == 2
    error_message = "node_pools must create one AzAPI nodePools child per map key."
  }

  assert {
    condition     = azapi_resource.node_pool["np-virt"].name == "np-virt"
    error_message = "Extra node pool ARM name must be the node_pools map key."
  }

  assert {
    condition     = azapi_resource.node_pool["np-virt"].body.properties.platform.vmSize == "Standard_D8s_v6"
    error_message = "np-virt must use Standard_D8s_v6."
  }

  assert {
    condition     = azapi_resource.node_pool["np-virt"].body.properties.labels[0].key == "workload" && azapi_resource.node_pool["np-virt"].body.properties.labels[0].value == "virtualization"
    error_message = "np-virt labels must be an ARM list of {key,value} matching the CLI."
  }

  assert {
    condition     = azapi_resource.node_pool["np-1"].body.properties.platform.availabilityZone == "1"
    error_message = "np-1 must pin workers to Azure availability zone 1."
  }

  assert {
    condition     = azapi_resource.node_pool["np-virt"].body.properties.platform.availabilityZone == "1"
    error_message = "np-virt must pin workers to Azure availability zone 1."
  }
}

run "node_pool_maps_cli_fields" {
  command = plan

  variables {
    node_pools = {
      np-1 = {
        vm_size  = "Standard_D4s_v6"
        replicas = 2
      }
      np-gpu = {
        vm_size                   = "Standard_D8s_v6"
        min_replicas              = 2
        max_replicas              = 6
        availability_zone         = "2"
        subnet_id                 = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/extra"
        disk_size_gib             = 128
        disk_storage_account_type = "Premium_LRS"
        disk_type                 = "Ephemeral"
        disk_encryption_set       = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Compute/diskEncryptionSets/des"
        encryption_at_host        = true
        auto_repair               = false
        node_drain_timeout        = 30
        labels = {
          dedicated = "gpu"
        }
        taints = [{
          key    = "dedicated"
          value  = "gpu"
          effect = "NoSchedule"
        }]
      }
    }
  }

  assert {
    condition     = try(azapi_resource.node_pool["np-gpu"].body.properties.replicas, null) == null
    error_message = "Autoscaling pools must omit replicas (CLI: cannot use with --min-replicas/--max-replicas)."
  }

  assert {
    condition     = azapi_resource.node_pool["np-gpu"].body.properties.autoScaling.min == 2 && azapi_resource.node_pool["np-gpu"].body.properties.autoScaling.max == 6
    error_message = "min_replicas/max_replicas must map to properties.autoScaling min/max."
  }

  assert {
    condition     = azapi_resource.node_pool["np-gpu"].body.properties.platform.subnetId == "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/extra"
    error_message = "subnet_id must override the cluster worker subnet (CLI --subnet-id)."
  }

  assert {
    condition     = azapi_resource.node_pool["np-gpu"].body.properties.platform.enableEncryptionAtHost == true
    error_message = "encryption_at_host must map to platform.enableEncryptionAtHost."
  }

  assert {
    condition     = azapi_resource.node_pool["np-gpu"].body.properties.platform.osDisk.diskType == "Ephemeral" && azapi_resource.node_pool["np-gpu"].body.properties.platform.osDisk.encryptionSetId == "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Compute/diskEncryptionSets/des" && azapi_resource.node_pool["np-gpu"].body.properties.platform.osDisk.sizeGiB == 128 && azapi_resource.node_pool["np-gpu"].body.properties.platform.osDisk.diskStorageAccountType == "Premium_LRS"
    error_message = "OS disk CLI flags must map to platform.osDisk."
  }

  assert {
    condition     = azapi_resource.node_pool["np-gpu"].body.properties.autoRepair == false
    error_message = "auto_repair must map to properties.autoRepair."
  }

  assert {
    condition     = azapi_resource.node_pool["np-gpu"].body.properties.nodeDrainTimeoutMinutes == 30
    error_message = "node_drain_timeout must map to properties.nodeDrainTimeoutMinutes."
  }

  assert {
    condition     = azapi_resource.node_pool["np-gpu"].body.properties.taints[0].key == "dedicated" && azapi_resource.node_pool["np-gpu"].body.properties.taints[0].effect == "NoSchedule"
    error_message = "taints must map to properties.taints {key,value,effect}."
  }

  assert {
    condition     = azapi_resource.node_pool["np-gpu"].body.properties.platform.availabilityZone == "2"
    error_message = "np-gpu must pin Azure availability zone 2."
  }
}

run "node_pool_rejects_partial_autoscaling" {
  command = plan

  variables {
    node_pools = {
      np-1 = {
        vm_size      = "Standard_D4s_v6"
        min_replicas = 2
      }
    }
  }

  expect_failures = [
    var.node_pools,
  ]
}

run "node_pool_taint_effect_must_be_valid" {
  command = plan

  variables {
    node_pools = {
      np-1 = {
        vm_size  = "Standard_D4s_v6"
        replicas = 2
        taints = [{
          key    = "dedicated"
          value  = "gpu"
          effect = "NoSchedulePlease"
        }]
      }
    }
  }

  expect_failures = [
    var.node_pools,
  ]
}

run "omitted_availability_zone_is_unpinned" {
  command = plan

  variables {
    node_pools = {
      np-1 = {
        vm_size  = "Standard_D4s_v6"
        replicas = 2
      }
    }
  }

  assert {
    condition     = try(azapi_resource.node_pool["np-1"].body.properties.platform.availabilityZone, null) == null
    error_message = "Omitting availability_zone must leave the pool unpinned (no platform.availabilityZone)."
  }

  assert {
    condition     = try(azapi_resource.node_pool["np-1"].body.properties.platform.subnetId, null) == null
    error_message = "Omitting subnet_id must leave platform.subnetId unset."
  }
}

run "availability_zone_must_be_azure_zone_number" {
  command = plan

  variables {
    node_pools = {
      np-1 = {
        vm_size           = "Standard_D4s_v6"
        replicas          = 2
        availability_zone = "uksouth-1"
      }
    }
  }

  expect_failures = [
    var.node_pools,
  ]
}

run "hcp_cluster_api_visibility_defaults_public" {
  command = plan

  assert {
    condition     = azapi_resource.hcp_cluster.body.properties.api.visibility == "Public"
    error_message = "Cluster API visibility must default to Public."
  }
}

run "hcp_cluster_api_visibility_private" {
  command = plan

  variables {
    api_visibility = "Private"
  }

  assert {
    condition     = azapi_resource.hcp_cluster.body.properties.api.visibility == "Private"
    error_message = "api_visibility=Private must set properties.api.visibility."
  }
}

run "hcp_cluster_ingress_visibility_defaults_public" {
  command = plan

  assert {
    condition     = azapi_resource.hcp_cluster.body.properties.ingress.type == "Public"
    error_message = "Cluster ingress visibility must default to Public."
  }
}

run "hcp_cluster_ingress_visibility_private" {
  command = plan

  variables {
    ingress_visibility = "Private"
  }

  assert {
    condition     = azapi_resource.hcp_cluster.body.properties.ingress.type == "Private"
    error_message = "ingress_visibility=Private must set properties.ingress.type."
  }
}

run "node_pool_version_must_be_enabled" {
  command = plan

  variables {
    node_pool_version = "9.9.9"
  }

  expect_failures = [
    azapi_resource.node_pool["np-1"],
  ]
}

run "cluster_version_must_be_enabled_stream" {
  command = plan

  variables {
    cluster_version = "3.11"
  }

  expect_failures = [
    azapi_resource.hcp_cluster,
  ]
}

run "managed_resource_group_defaults_from_cluster_name" {
  command = plan

  variables {
    managed_resource_group_name = null
  }

  assert {
    condition     = azapi_resource.hcp_cluster.body.properties.platform.managedResourceGroup == "test-cluster-managed"
    error_message = "managed_resource_group_name must default to <cluster_name>-managed."
  }
}

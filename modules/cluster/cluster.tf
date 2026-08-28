# HCP cluster and default node pool via AzAPI (2026-06-30-preview).
# schema_validation_enabled = false: preview ARM schemas lag the API.
# Destroy of the last node pool is blocked (OCPBUGS-86702); scripts/destroy.sh
# removes azapi_resource.node_pool from state then runs terraform destroy.

resource "azapi_resource" "hcp_cluster" {
  type                      = "Microsoft.RedHatOpenShift/hcpOpenShiftClusters@${local.hcp_api_version}"
  parent_id                 = var.resource_group_id
  name                      = var.cluster_name
  location                  = var.location
  schema_validation_enabled = false
  tags                      = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = tolist(var.cluster_identity_ids)
  }

  body = {
    properties = {
      version = {
        id           = var.cluster_version
        channelGroup = var.cluster_channel
      }
      dns = {}
      network = {
        networkType = "OVNKubernetes"
        podCidr     = var.pod_cidr
        serviceCidr = var.service_cidr
        machineCidr = var.address_prefix
        hostPrefix  = var.host_prefix
      }
      etcd = {
        dataEncryption = {
          keyManagementMode = "CustomerManaged"
          customerManaged = {
            encryptionType = "KMS"
            kms = {
              activeKey = {
                name    = var.etcd_encryption_key_name
                version = var.etcd_key_version
              }
              vaultName  = var.key_vault_name
              visibility = var.vault_visibility
            }
          }
        }
      }
      api = {
        visibility = var.api_visibility
      }
      ingress = {
        type = var.ingress_visibility
      }
      clusterImageRegistry = {
        state = var.cluster_image_registry_state
      }
      platform = {
        managedResourceGroup    = local.managed_resource_group_name
        subnetId                = var.worker_subnet_id
        vnetIntegrationSubnetId = var.vnet_integration_subnet_id
        outboundType            = var.outbound_type
        networkSecurityGroupId  = var.nsg_id
        operatorsAuthentication = {
          userAssignedIdentities = {
            controlPlaneOperators  = var.control_plane_operators
            dataPlaneOperators     = var.data_plane_operators
            serviceManagedIdentity = var.service_identity_id
          }
        }
      }
    }
  }

  response_export_values = ["properties"]

  timeouts {
    create = "120m"
    update = "120m"
    delete = "120m"
  }

  lifecycle {
    precondition {
      condition     = contains(local.hcp_cluster_streams, var.cluster_version)
      error_message = "cluster_version ${var.cluster_version} is not an enabled ${var.cluster_channel} stream in ${var.location}. Available: ${join(", ", local.hcp_cluster_streams)}."
    }
  }
}

resource "azapi_resource" "node_pool" {
  type                      = "Microsoft.RedHatOpenShift/hcpOpenShiftClusters/nodePools@${local.hcp_api_version}"
  parent_id                 = azapi_resource.hcp_cluster.id
  name                      = var.node_pool_name
  location                  = var.location
  schema_validation_enabled = false
  tags                      = local.tags

  body = {
    properties = {
      version = {
        id           = var.node_pool_version
        channelGroup = var.node_pool_channel
      }
      platform = {
        subnetId = var.worker_subnet_id
        vmSize   = var.node_pool_vm_size
        osDisk = {
          sizeGiB                = var.node_pool_disk_size_gib
          diskStorageAccountType = var.node_pool_disk_storage_account_type
        }
      }
      replicas = var.node_pool_replicas
    }
  }

  timeouts {
    create = "90m"
    update = "90m"
    delete = "90m"
  }

  lifecycle {
    precondition {
      condition     = contains(local.hcp_node_pool_versions, var.node_pool_version)
      error_message = "node_pool_version ${var.node_pool_version} is not an enabled ${var.node_pool_channel} version in ${var.location}. Available: ${join(", ", local.hcp_node_pool_versions)}."
    }
  }
}

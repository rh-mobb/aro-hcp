locals {
  tags = merge(var.tags, {
    project = "aro-hcp-reference"
  })

  # Built-in role definition GUIDs (0.0.2 az aro hcp guide)
  role_ids = {
    service_managed_identity = "c0ff367d-66d8-445e-917c-583feb0ef0d4"
    cluster_api_provider     = "88366f10-ed47-4cc0-9fab-c8a06148393e"
    control_plane_operator   = "fc0c873f-45e9-4d0d-a7d1-585aab30c6ed"
    cloud_controller_manager = "a1f96423-95ce-4224-ab27-4e3dc72facd4"
    ingress_operator         = "0336e1d3-7a87-462b-b6db-342b63f7802c"
    file_storage_operator    = "0d7aedc0-15fd-4a67-a412-efad370c947e"
    image_registry_operator  = "8b32b316-c2f5-4ddf-b05b-83dacd2d08b5"
    network_operator         = "be7a6435-15ae-4171-8f30-4a343eff9e8f"
    key_vault_crypto_user    = "12338af0-0e69-4776-bea7-57ae8d297424"
    reader                   = "acdd72a7-3385-48ef-bd42-f606fba81ae7"
    federated_credential     = "ef318e2a-8334-4a05-9e4a-295a196c6a6e"
  }

  identity_names = {
    service                  = "${var.cluster_name}-service"
    cluster_api_azure        = "${var.cluster_name}-cluster-api-azure"
    control_plane            = "${var.cluster_name}-control-plane"
    cloud_controller_manager = "${var.cluster_name}-cloud-controller-manager"
    ingress                  = "${var.cluster_name}-ingress"
    disk_csi_driver          = "${var.cluster_name}-disk-csi-driver"
    file_csi_driver          = "${var.cluster_name}-file-csi-driver"
    image_registry           = "${var.cluster_name}-image-registry"
    cloud_network_config     = "${var.cluster_name}-cloud-network-config"
    kms                      = "${var.cluster_name}-kms"
    dp_disk_csi_driver       = "${var.cluster_name}-dp-disk-csi-driver"
    dp_file_csi_driver       = "${var.cluster_name}-dp-file-csi-driver"
    dp_image_registry        = "${var.cluster_name}-dp-image-registry"
  }

  hcp_api_version             = "2026-06-30-preview"
  managed_resource_group_name = coalesce(var.managed_resource_group_name, "${var.cluster_name}-managed")
  etcd_encryption_key_name    = "etcd-data-kms-encryption-key"
}

# Changelog

Notable **committed** changes to this reference deployment.

Entries are added at **commit time** from that commit’s diff. Do not log in-progress, debug, or reverted work.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Initial ARO HCP reference deployment: Terraform prerequisites, `az aro hcp` lifecycle scripts, docs, CI, and bats tests.
- AzAPI `hcpOpenShiftClusters` and default `nodePools` (`2026-06-30-preview`) in Terraform; `make apply` is the cluster path
- `scripts/destroy.sh`: state-rm the default node pool (OCPBUGS-86702 last-pool DELETE 409) then `terraform destroy`
- Optional `API_VISIBILITY` (`Public` / `Private`, create-time) via Terraform

### Changed
- `make cluster` / `make nodepool` are aliases of `make apply`; CLI create remains for extra pools and fallback
- VNet integration subnet `depends_on` other VNet writers to avoid concurrent subnet update conflicts
- Cluster RG destroy allows leftover resources (`prevent_deletion_if_contains_resources = false`)

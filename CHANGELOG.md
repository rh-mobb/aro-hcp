# Changelog

Notable **committed** changes to this reference deployment.

Entries are added at **commit time** from that commit’s diff. Do not log in-progress, debug, or reverted work.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `make cluster.<profile>.sshuttle.connect` / `sshuttle.disconnect` / `sshuttle.status` — background sshuttle via jump box (`clusters/<profile>/sshuttle.pid`)
- Per-cluster operator layout: `clusters/<profile>/terraform.tfvars`, local state, and `make cluster.<profile>.<operation>` via `Makefile.cluster`
- Terraform modules (`modules/network`, `identities`, `cluster`, `jumpbox`) with root composition in `terraform/`
- Example profiles [`clusters/public`](clusters/public/) and [`clusters/private`](clusters/private/) (public vs private API/ingress + jump box)
- `scripts/private-dns.sh` and `make cluster.<profile>.private-dns` — customer Private DNS for private API/ingress (operator stopgap until platform DNS)
- `make cluster.<profile>.console-secret` — retry console OAuth secret apply (private API + sshuttle)
- MkDocs operator site ([`mkdocs.yml`](mkdocs.yml), GitHub Pages workflow) with prerequisites, quick start, external-auth guide, and Red Hat brand styling
- `hack/versions` — plan-time OpenShift version validation per region

### Changed
- MkDocs theme: use Material `default` / `slate` palettes (match ROSA validated-pattern docs) instead of custom RHDS token overrides
- `make bootstrap` renamed to `make setup` (`scripts/setup.sh`); `make bootstrap` remains as a deprecated alias
- Scripts read cluster config from Terraform outputs with fallback to `clusters/<profile>/terraform.tfvars`; per-cluster `TF_DATA_DIR`
- `destroy.sh`: correct state path for node-pool state-rm (OCPBUGS-86702); wait and retry when cluster is already deleting in Azure
- `external-auth-delete` warns and continues if `oc` cannot reach private API
- `jump-pub-check` requires `jump_ssh_source_prefix` in tfvars or `TF_VAR_jump_ssh_source_prefix` when jump is enabled
- Architecture and README docs aligned with modular layout and least-privilege permissions per deploy step

### Removed
- `config/cluster.env.example` and monolithic `terraform/*.tf` resources (replaced by modules + per-cluster tfvars)

### Fixed
- `make cluster.<profile>.kubeconfig` failed with “Cluster public does not exist” when GNU Make exported `CLUSTER_NAME` from the profile name
- `make cluster.<profile>.destroy` skipped node-pool state-rm when `TF_DATA_DIR` pointed at the wrong cluster

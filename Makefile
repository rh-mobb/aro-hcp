.DEFAULT_GOAL := help

SHELL := /bin/bash
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TF_DIR := $(ROOT_DIR)/terraform
MODULES_DIR := $(ROOT_DIR)/modules
VERSIONS_TF_DIR := $(ROOT_DIR)/hack/versions
SCRIPTS := $(ROOT_DIR)/scripts

# Leftover shell TF_VAR_* still reach `terraform test`. Unset the mapped names
# so CI without cluster tfvars uses Terraform defaults.
TF_VARS_TO_UNSET := TF_VAR_location TF_VAR_cluster_name TF_VAR_resource_group_name \
	TF_VAR_vnet_name TF_VAR_subnet_name TF_VAR_vnet_integration_subnet_name TF_VAR_nsg_name \
	TF_VAR_managed_resource_group_name TF_VAR_cluster_version TF_VAR_cluster_channel \
	TF_VAR_node_pool_name TF_VAR_node_pool_replicas TF_VAR_node_pool_vm_size \
	TF_VAR_node_pool_version TF_VAR_node_pool_channel TF_VAR_api_visibility TF_VAR_ingress_visibility \
	TF_VAR_enable_jumpbox TF_VAR_jump_ssh_source_prefix TF_VAR_jump_ssh_public_key \
	TF_VAR_jump_ssh_private_key_path TF_VAR_pull_secret_path TF_VAR_pull_secret_key_vault_secret_name

.PHONY: help fmt lint test setup bootstrap docs-venv docs-preview docs-serve docs-build \
	cluster.%

help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_.-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-28s %s\n", $$1, $$2}'
	@echo ""
	@echo "Cluster operations: make cluster.<name>.<operation>"
	@echo "  init plan apply destroy kubeconfig external-auth external-auth-delete console-secret"
	@echo "  jump-key jump sshuttle.connect sshuttle.disconnect versions setup bootstrap private-dns private-dns-delete"
	@echo "Examples:"
	@echo "  make cluster.public.init"
	@echo "  make cluster.public.apply"
	@echo "  make cluster.private.jump-key"

# Pattern: make cluster.<cluster-name>.<operation>
cluster.%:
	@CLUSTER_PROFILE=$$(echo "$@" | cut -d'.' -f2); \
	OPERATION=$$(echo "$@" | cut -d'.' -f3-); \
	if [ -z "$$CLUSTER_PROFILE" ] || [ -z "$$OPERATION" ]; then \
		echo "Usage: make cluster.<name>.<operation>" >&2; \
		echo "Example: make cluster.public.apply" >&2; \
		exit 1; \
	fi; \
	if [ ! -d "$(ROOT_DIR)/clusters/$$CLUSTER_PROFILE" ]; then \
		echo "Cluster directory clusters/$$CLUSTER_PROFILE does not exist" >&2; \
		ls -1 "$(ROOT_DIR)/clusters/" 2>/dev/null | sed 's/^/  - /' || true; \
		exit 1; \
	fi; \
	$(MAKE) -f Makefile.cluster CLUSTER_PROFILE=$$CLUSTER_PROFILE $$OPERATION

fmt: ## Format Terraform and shell scripts
	terraform -chdir=$(TF_DIR) fmt -recursive
	terraform -chdir=$(MODULES_DIR)/network fmt
	terraform -chdir=$(MODULES_DIR)/identities fmt
	terraform -chdir=$(MODULES_DIR)/cluster fmt
	terraform -chdir=$(MODULES_DIR)/jumpbox fmt
	terraform -chdir=$(VERSIONS_TF_DIR) fmt
	@command -v shfmt >/dev/null && shfmt -w -i 2 -ci -bn $(SCRIPTS) || echo "shfmt not installed; skipping"

lint: ## Run linters (terraform validate/tflint, shellcheck)
	terraform -chdir=$(TF_DIR) init -backend=false -input=false
	terraform -chdir=$(TF_DIR) validate
	terraform -chdir=$(MODULES_DIR)/network init -backend=false -input=false && terraform -chdir=$(MODULES_DIR)/network validate
	terraform -chdir=$(MODULES_DIR)/identities init -backend=false -input=false && terraform -chdir=$(MODULES_DIR)/identities validate
	terraform -chdir=$(MODULES_DIR)/cluster init -backend=false -input=false && terraform -chdir=$(MODULES_DIR)/cluster validate
	terraform -chdir=$(MODULES_DIR)/jumpbox init -backend=false -input=false && terraform -chdir=$(MODULES_DIR)/jumpbox validate
	terraform -chdir=$(VERSIONS_TF_DIR) init -backend=false -input=false
	terraform -chdir=$(VERSIONS_TF_DIR) validate
	@command -v tflint >/dev/null && (cd $(TF_DIR) && tflint --init && tflint) || echo "tflint not installed; skipping"
	@command -v tflint >/dev/null && (cd $(MODULES_DIR)/network && tflint --init && tflint) || true
	@command -v tflint >/dev/null && (cd $(MODULES_DIR)/identities && tflint --init && tflint) || true
	@command -v tflint >/dev/null && (cd $(MODULES_DIR)/cluster && tflint --init && tflint) || true
	@command -v tflint >/dev/null && (cd $(MODULES_DIR)/jumpbox && tflint --init && tflint) || true
	@command -v shellcheck >/dev/null && (cd $(SCRIPTS) && shellcheck --external-sources *.sh) || echo "shellcheck not installed; skipping"
	@command -v shfmt >/dev/null && shfmt -d -i 2 -ci -bn $(SCRIPTS) || true
	@if command -v oc >/dev/null 2>&1; then \
		oc kustomize $(ROOT_DIR)/gitops/overlays/public >/dev/null; \
		oc kustomize $(ROOT_DIR)/gitops/overlays/private >/dev/null; \
		echo "gitops kustomize overlays ok"; \
	elif command -v kubectl >/dev/null 2>&1; then \
		kubectl kustomize $(ROOT_DIR)/gitops/overlays/public >/dev/null; \
		kubectl kustomize $(ROOT_DIR)/gitops/overlays/private >/dev/null; \
		echo "gitops kustomize overlays ok"; \
	else \
		echo "oc/kubectl not installed; skipping gitops kustomize"; \
	fi

test: lint ## Run unit tests (terraform test + bats)
	unset $(TF_VARS_TO_UNSET); \
	terraform -chdir=$(MODULES_DIR)/network test; \
	terraform -chdir=$(MODULES_DIR)/identities test; \
	terraform -chdir=$(MODULES_DIR)/cluster test; \
	terraform -chdir=$(MODULES_DIR)/jumpbox test; \
	terraform -chdir=$(TF_DIR) test; \
	terraform -chdir=$(VERSIONS_TF_DIR) test
	@if command -v bats >/dev/null; then bats $(ROOT_DIR)/tests/bats; else echo "bats not installed; skipping"; fi

setup: ## Install tools and az aro hcp extension (once per machine)
	bash $(SCRIPTS)/setup.sh

bootstrap: ## Deprecated: use make setup
	@echo "WARNING: make bootstrap is deprecated; use make setup" >&2
	$(MAKE) setup

# Documentation (MkDocs Material)
VENV_DOCS ?= .venv-docs
DOCS_MKDOCS := $(VENV_DOCS)/bin/mkdocs
DOCS_PIP := $(VENV_DOCS)/bin/pip

docs-venv: ## Create docs virtualenv and install requirements-docs.txt
	@if ! command -v python3 >/dev/null 2>&1; then \
		echo "Error: python3 is required for documentation preview" >&2; \
		exit 1; \
	fi
	@if [ ! -d "$(VENV_DOCS)" ]; then \
		echo "Creating docs virtualenv at $(VENV_DOCS)..."; \
		python3 -m venv "$(VENV_DOCS)"; \
	fi
	@$(DOCS_PIP) install -q -r requirements-docs.txt
	@echo "Docs dependencies ready"

docs-preview: docs-venv ## Serve docs at http://127.0.0.1:8000/aro-hcp/
	@echo "Documentation preview: http://127.0.0.1:8000/aro-hcp/"
	@echo "Press Ctrl+C to stop"
	@$(DOCS_MKDOCS) serve

docs-serve: docs-preview ## Alias for docs-preview

docs-build: docs-venv ## Build documentation site (strict link checking)
	@$(DOCS_MKDOCS) build --strict
	@echo "Documentation built successfully"

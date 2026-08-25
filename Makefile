.DEFAULT_GOAL := help

SHELL := /bin/bash
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TF_DIR := $(ROOT_DIR)/terraform
CONFIG_FILE := $(ROOT_DIR)/config/cluster.env
SCRIPTS := $(ROOT_DIR)/scripts

export CONFIG_FILE

# Load cluster.env if present for variable overrides
ifneq (,$(wildcard $(CONFIG_FILE)))
include $(CONFIG_FILE)
export
endif

TF_VAR_location ?= $(LOCATION)
TF_VAR_cluster_name ?= $(CLUSTER_NAME)
TF_VAR_resource_group_name ?= $(RESOURCE_GROUP)
TF_VAR_vnet_name ?= $(VNET_NAME)
TF_VAR_subnet_name ?= $(SUBNET_NAME)
TF_VAR_vnet_integration_subnet_name ?= $(VNET_INTEGRATION_SUBNET_NAME)
TF_VAR_nsg_name ?= $(NSG_NAME)

.PHONY: help fmt lint test bootstrap init plan apply cluster nodepool all \
	kubeconfig revoke-credentials versions external-auth external-auth-delete destroy

help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_.-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-22s %s\n", $$1, $$2}'

fmt: ## Format Terraform and shell scripts
	terraform -chdir=$(TF_DIR) fmt -recursive
	@command -v shfmt >/dev/null && shfmt -w -i 2 -ci -bn $(SCRIPTS) || echo "shfmt not installed; skipping"

lint: ## Run linters (terraform validate/tflint, shellcheck)
	terraform -chdir=$(TF_DIR) init -backend=false -input=false
	terraform -chdir=$(TF_DIR) validate
	@command -v tflint >/dev/null && (cd $(TF_DIR) && tflint --init && tflint) || echo "tflint not installed; skipping"
	@command -v shellcheck >/dev/null && shellcheck $(SCRIPTS)/*.sh || echo "shellcheck not installed; skipping"
	@command -v shfmt >/dev/null && shfmt -d -i 2 -ci -bn $(SCRIPTS) || true

test: lint ## Run unit tests (terraform test + bats)
	terraform -chdir=$(TF_DIR) test
	@command -v bats >/dev/null && bats $(ROOT_DIR)/tests/bats || echo "bats not installed; skipping"

bootstrap: ## Install tools and az aro hcp extension
	bash $(SCRIPTS)/bootstrap.sh

init: ## Terraform init
	terraform -chdir=$(TF_DIR) init

plan: init ## Terraform plan
	terraform -chdir=$(TF_DIR) plan

apply: init ## Terraform apply (prerequisites)
	terraform -chdir=$(TF_DIR) apply -auto-approve

cluster: bootstrap ## Create or show cluster (idempotent)
	bash $(SCRIPTS)/cluster.sh create

nodepool: bootstrap ## Create default node pool (idempotent)
	bash $(SCRIPTS)/nodepool.sh create

all: bootstrap apply cluster nodepool ## Full deploy: prereqs + cluster + nodepool
	@echo "Deploy complete. Run: make kubeconfig"

kubeconfig: bootstrap ## Request admin kubeconfig
	bash $(SCRIPTS)/credentials.sh request

revoke-credentials: bootstrap ## Revoke admin credentials
	bash $(SCRIPTS)/credentials.sh revoke

versions: bootstrap ## List available OpenShift versions
	bash $(SCRIPTS)/versions.sh

external-auth: bootstrap kubeconfig ## Configure Entra external auth + console
	bash $(SCRIPTS)/external-auth.sh create

external-auth-delete: bootstrap ## Remove external auth and Entra app
	bash $(SCRIPTS)/external-auth.sh delete

destroy: bootstrap ## Tear down cluster, node pools, and terraform prereqs
	-bash $(SCRIPTS)/external-auth.sh delete
	-bash $(SCRIPTS)/nodepool.sh delete
	-bash $(SCRIPTS)/cluster.sh delete
	terraform -chdir=$(TF_DIR) destroy -auto-approve

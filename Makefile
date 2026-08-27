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

# Export TF_VAR_* only when the Make variable is non-empty. An empty export
# (CI without cluster.env) overrides Terraform defaults and breaks tests
# (TF_VAR_node_pool_replicas="" is not a number; TF_VAR_vnet_name="" fails azurerm).
# := so cluster.env wins over leftover shell TF_VAR_* for Make targets.
define export_tf_if_set
ifneq ($$(strip $$($(1))),)
export TF_VAR_$(2) := $$($(1))
endif
endef

$(eval $(call export_tf_if_set,LOCATION,location))
$(eval $(call export_tf_if_set,CLUSTER_NAME,cluster_name))
$(eval $(call export_tf_if_set,RESOURCE_GROUP,resource_group_name))
$(eval $(call export_tf_if_set,VNET_NAME,vnet_name))
$(eval $(call export_tf_if_set,SUBNET_NAME,subnet_name))
$(eval $(call export_tf_if_set,VNET_INTEGRATION_SUBNET_NAME,vnet_integration_subnet_name))
$(eval $(call export_tf_if_set,NSG_NAME,nsg_name))
$(eval $(call export_tf_if_set,MANAGED_RESOURCE_GROUP,managed_resource_group_name))
$(eval $(call export_tf_if_set,CLUSTER_VERSION,cluster_version))
$(eval $(call export_tf_if_set,CLUSTER_CHANNEL,cluster_channel))
$(eval $(call export_tf_if_set,NODEPOOL_NAME,node_pool_name))
$(eval $(call export_tf_if_set,NODEPOOL_REPLICAS,node_pool_replicas))
$(eval $(call export_tf_if_set,NODEPOOL_VM_SIZE,node_pool_vm_size))
$(eval $(call export_tf_if_set,NODEPOOL_VERSION,node_pool_version))
$(eval $(call export_tf_if_set,NODEPOOL_CHANNEL,node_pool_channel))
$(eval $(call export_tf_if_set,API_VISIBILITY,api_visibility))

TF_VARS_TO_UNSET := TF_VAR_location TF_VAR_cluster_name TF_VAR_resource_group_name \
	TF_VAR_vnet_name TF_VAR_subnet_name TF_VAR_vnet_integration_subnet_name TF_VAR_nsg_name \
	TF_VAR_managed_resource_group_name TF_VAR_cluster_version TF_VAR_cluster_channel \
	TF_VAR_node_pool_name TF_VAR_node_pool_replicas TF_VAR_node_pool_vm_size \
	TF_VAR_node_pool_version TF_VAR_node_pool_channel TF_VAR_api_visibility

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
	@command -v shellcheck >/dev/null && (cd $(SCRIPTS) && shellcheck --external-sources *.sh) || echo "shellcheck not installed; skipping"
	@command -v shfmt >/dev/null && shfmt -d -i 2 -ci -bn $(SCRIPTS) || true

test: lint ## Run unit tests (terraform test + bats)
	unset $(TF_VARS_TO_UNSET); \
	terraform -chdir=$(TF_DIR) test
	@command -v bats >/dev/null && bats $(ROOT_DIR)/tests/bats || echo "bats not installed; skipping"

bootstrap: ## Install tools and az aro hcp extension
	bash $(SCRIPTS)/bootstrap.sh

init: ## Terraform init
	terraform -chdir=$(TF_DIR) init

plan: init ## Terraform plan
	terraform -chdir=$(TF_DIR) plan

apply: init ## Terraform apply (prereqs + cluster + default node pool)
	terraform -chdir=$(TF_DIR) apply -auto-approve

cluster: apply ## Create cluster via Terraform (alias of apply)

nodepool: apply ## Create default node pool via Terraform (alias of apply)

all: bootstrap apply ## Full deploy: prereqs + cluster + default nodepool
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

destroy: bootstrap init ## Tear down: state-rm last pool then terraform destroy (OCPBUGS-86702)
	-bash $(SCRIPTS)/external-auth.sh delete
	bash $(SCRIPTS)/destroy.sh

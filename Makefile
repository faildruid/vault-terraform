###############################################################################
# Makefile — Vault Terraform developer workflow
#
# Usage:
#   make <target> [ENV=dev|staging|prod]
#
# ENV defaults to "dev" if not specified.
# All targets that interact with Terraform require:
#   - VAULT_ADDR exported in the shell
#   - VAULT_TOKEN exported (or vault login run first)
###############################################################################

.DEFAULT_GOAL := help
ENV           ?= dev
TFVARS        := environments/$(ENV)/terraform.tfvars
BACKEND       := environments/$(ENV)/backend.hcl
TF            := terraform

.PHONY: help init validate fmt fmt-check lint plan apply apply-auto destroy \
        output output-json clean vault-status vault-login-dev \
        list-engines list-approles list-policies test-approle

##
## ── Terraform targets ────────────────────────────────────────────────────────
##

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialise Terraform with env-specific backend (ENV=dev|staging|prod)
	$(TF) init -upgrade -backend-config=$(BACKEND)

validate: ## Validate HCL syntax and provider schema conformance
	$(TF) validate

fmt: ## Format all .tf files in-place (recursive)
	$(TF) fmt -recursive

fmt-check: ## Check formatting without writing — exits non-zero if unformatted (CI)
	$(TF) fmt -recursive -check -diff

lint: ## Run tflint on all modules (install: https://github.com/terraform-linters/tflint)
	tflint --recursive --format compact

plan: ## Generate and display execution plan, save to tfplan-<ENV>
	$(TF) plan \
	  -var-file=$(TFVARS) \
	  -out=tfplan-$(ENV) \
	  -detailed-exitcode

apply: ## Apply a saved plan file produced by 'make plan' (ENV=dev|staging|prod)
	$(TF) apply tfplan-$(ENV)

apply-auto: ## Plan and apply in one step without confirmation (USE WITH CAUTION)
	$(TF) apply -var-file=$(TFVARS) -auto-approve

destroy: ## Destroy all resources for the environment — DESTRUCTIVE, requires confirmation
	@echo "╔══════════════════════════════════════════════════════╗"
	@echo "║  WARNING: This will DESTROY all Vault resources      ║"
	@echo "║  for environment: $(ENV)                             ║"
	@echo "╚══════════════════════════════════════════════════════╝"
	@read -p "  Type the environment name to confirm [$(ENV)]: " confirm && \
	  [ "$$confirm" = "$(ENV)" ] || (echo "Aborted." && exit 1)
	$(TF) destroy -var-file=$(TFVARS) -auto-approve

output: ## Show all non-sensitive outputs
	$(TF) output

output-json: ## Show all outputs as JSON — EXPOSES SENSITIVE VALUES, handle with care
	@echo "Warning: this output includes sensitive secret_id values."
	$(TF) output -json

clean: ## Remove local Terraform working files (.terraform/, plan files)
	rm -rf .terraform tfplan-* crash.log .terraform.lock.hcl

##
## ── Vault helper targets ─────────────────────────────────────────────────────
## These require VAULT_ADDR and VAULT_TOKEN to be set in the environment.
##

vault-status: ## Check Vault cluster health and seal status
	vault status

vault-login-dev: ## Login to the dev Vault cluster via OIDC (adjust method as needed)
	vault login -method=oidc -path=oidc

list-engines: ## List all mounted secret engines with their types and paths
	vault secrets list -detailed

list-approles: ## List all AppRole roles registered under auth/approle
	vault list auth/approle/role

list-policies: ## List all Vault policies
	vault policy list

test-approle: ## Test AppRole login for a named role (usage: make test-approle ROLE=nwpci_awx_nwauto)
	@echo "Reading credentials from Terraform output for role: $(ROLE)"
	$(eval ROLE_ID  := $(shell $(TF) output -json approle_role_ids  | jq -r '.$(ROLE)'))
	$(eval SECRET_ID := $(shell $(TF) output -json approle_secret_ids | jq -r '.$(ROLE)'))
	@echo "Attempting AppRole login..."
	vault write auth/approle/login role_id=$(ROLE_ID) secret_id=$(SECRET_ID)

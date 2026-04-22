###############################################################################
# environments/dev/backend.hcl
#
# Remote state backend configuration for the dev environment.
# Pass to terraform init with: terraform init -backend-config=environments/dev/backend.hcl
# Or via Makefile: make init ENV=dev
#
# Using a per-environment backend.hcl file (rather than hardcoding backend
# config in main.tf) allows the same Terraform root module to target different
# state locations per environment without changing source code.
#
# Uncomment and populate the S3 backend block when ready for remote state.
# Local state (no backend block) is acceptable for individual developer use only.
###############################################################################

# bucket         = "tfstate-vault-config-dev"
# key            = "vault/network-pci/dev/terraform.tfstate"
# region         = "eu-west-1"
# encrypt        = true            # AES-256 SSE — required for secrets in state
# dynamodb_table = "tfstate-lock-dev"  # Prevents concurrent apply races
# role_arn       = "arn:aws:iam::123456789012:role/terraform-state-dev"

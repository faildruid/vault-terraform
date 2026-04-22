###############################################################################
# variables.tf — Root input variables
#
# All variables must be supplied either via terraform.tfvars,
# environment-specific var files (environments/<env>/terraform.tfvars),
# or TF_VAR_* environment variables.
#
# Sensitive variables (marked sensitive=true) are redacted in plan output
# and in Terraform Cloud/Enterprise run logs.
# They are still stored in plain text in local state files — use encrypted
# remote state (S3+SSE or Terraform Cloud) in shared environments.
###############################################################################

variable "vault_address" {
  description = <<-EOD
    Full URL of the Vault server, including scheme and port.
    Example: https://vault.example.internal:8200
    Used by the hashicorp/vault provider as the API endpoint.
    Must be reachable from the machine running terraform apply.
  EOD
  type    = string
  default = "https://vault.example.internal:8200"
}

variable "environment" {
  description = <<-EOD
    Deployment environment identifier. Controls KV path segments and metadata.
    Used in:
      - SMS KV paths: global/vault/<environment>/sms/<role>
      - AWX KV paths: global/vault/dev/<environment>/<role>
      - Sample secret paths: sample/<environment>/devices/<device>
      - custom_metadata.environment field on all secrets
    Allowed values: dev | staging | prod
  EOD
  type = string

  # Validation prevents accidental path injection from typos.
  # An invalid value fails immediately at plan time with a clear error message.
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "approle_token_ttl" {
  description = <<-EOD
    Default TTL for tokens issued on AppRole login.
    Controls how long an application can use a token before re-authenticating.
    Format: Vault duration string (e.g. "1h", "30m", "3600s").
    This value is applied at the role level and overrides the auth mount default.
    Keep short to limit blast radius if a token is leaked.
  EOD
  type    = string
  default = "1h"
}

variable "approle_token_max_ttl" {
  description = <<-EOD
    Maximum TTL for tokens issued on AppRole login.
    A token cannot be renewed beyond this TTL even if the renewal request
    specifies a longer increment. Applications must re-authenticate after
    this duration regardless of renewals.
    Format: Vault duration string (e.g. "4h", "8h").
    Must be >= approle_token_ttl.
  EOD
  type    = string
  default = "4h"
}

variable "credential_expiry_date" {
  description = <<-EOD
    ISO 8601 date stored in custom_metadata.expiry_date on all secrets.
    Used by external rotation tooling to identify credentials that are
    approaching or past their expiry window.
    Example: "2027-04-01"
    This is informational metadata only — Vault does not enforce it.
    Automated rotation tooling should read and act on this field.
  EOD
  type    = string
  default = "2027-04-01"
}

variable "sample_secret_password" {
  description = <<-EOD
    Password stored in the sample device secrets created in each KV engine.
    Marked sensitive so it is redacted in plan output and state display.
    In CI pipelines, inject via: export TF_VAR_sample_secret_password="..."
    Never hardcode a real password here or in terraform.tfvars.
    Default is a placeholder that will fail any real authentication attempt.
  EOD
  type      = string
  sensitive = true
  default   = "CHANGE_ME_IN_TFVARS"
}

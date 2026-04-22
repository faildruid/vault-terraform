###############################################################################
# modules/kv_secret/variables.tf
###############################################################################

variable "mount_path" {
  description = <<-EOD
    KV v2 engine mount path where the secret will be written.
    Must match an existing vault_mount resource.
    Example: "network-atm-secrets"
    All AppRole credentials are stored in the ATM engine regardless of which
    domain the role belongs to — this centralises credential management and
    avoids requiring each engine's policy to cross-reference another engine.
  EOD
  type = string
}

variable "secret_path" {
  description = <<-EOD
    Path within the mount at which the secret is written. No leading slash.
    The Vault API will store this at <mount>/data/<secret_path>.
    The vault CLI and UI present it as <mount>/<secret_path>.

    Conventions:
      SMS credentials: global/vault/<env>/sms/<role-name>
        e.g. global/vault/dev/sms/nwpci-sms-nwauto
      AWX credentials: global/vault/dev/<env>/<role-name>
        e.g. global/vault/dev/dev/nwpci-awx-nwauto

    Path components must not contain characters that conflict with Vault's
    path routing: avoid #, ?, and leading/trailing slashes.
  EOD
  type = string
}

variable "role_id" {
  description = <<-EOD
    AppRole role_id to store as the "role_id" field in the secret payload.
    Sourced from the approle module's role_id output.
    Not sensitive by itself but stored alongside secret_id — treat the
    combined secret as confidential.
  EOD
  type = string
}

variable "secret_id" {
  description = <<-EOD
    AppRole bootstrap secret_id to store as the "secret_id" field.
    Sensitive — marked sensitive=true so Vault's provider redacts it in
    plan output. Still stored in Terraform state; requires encrypted state.
    Sourced from the approle module's secret_id output.
    Consuming applications MUST rotate this after first retrieval.
  EOD
  type      = string
  sensitive = true
}

variable "custom_metadata" {
  description = <<-EOD
    Map of string key/value pairs stored as KV v2 custom_metadata.
    All values must be strings — encode complex structures with jsonencode().
    Metadata is NOT versioned: it is shared across all secret versions.
    Updating metadata does NOT create a new secret version.

    Expected keys:
      expiry_date         — ISO 8601 credential expiry date
      pwd_rotation_data   — JSON-encoded rotation context string
      pwd_rotation_method — rotation mode ("auto" | "manual")
      approle_name        — role name for human reference
      environment         — target environment (dev | staging | prod)
  EOD
  type    = map(string)
  default = {}
}

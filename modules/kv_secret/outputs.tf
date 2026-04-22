###############################################################################
# modules/kv_secret/outputs.tf
###############################################################################

output "full_secret_path" {
  description = <<-EOD
    Full KV v2 API path to the secret data, including the /data/ prefix.
    Format: <mount>/data/<secret_path>
    Use this with the raw Vault HTTP API:
      GET /v1/<full_secret_path>
    The vault CLI accepts paths without /data/:
      vault kv get <mount>/<secret_path>
    Exposed in root outputs.tf as kv_credential_paths for operator reference.
  EOD
  value = "${var.mount_path}/data/${var.secret_path}"
}

output "secret_path" {
  description = <<-EOD
    The relative path within the mount as stored by Terraform.
    Matches vault_kv_secret_v2.this.name — the path Vault acknowledges.
    Use for vault CLI commands: vault kv get <mount>/<secret_path>
  EOD
  value = vault_kv_secret_v2.this.name
}

output "mount_path" {
  description = "KV engine mount path where this secret is stored."
  value       = var.mount_path
}

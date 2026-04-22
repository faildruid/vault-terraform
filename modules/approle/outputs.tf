###############################################################################
# modules/approle/outputs.tf
###############################################################################

output "role_name" {
  description = <<-EOD
    The AppRole role name as registered in Vault.
    Matches var.role_name — exposed as an output so callers can reference
    the role name without repeating the string (e.g. in KV secret paths).
  EOD
  value = vault_approle_auth_backend_role.this.role_name
}

output "role_id" {
  description = <<-EOD
    The stable role_id UUID assigned by Vault to this AppRole.
    role_id is the "username" half of the AppRole credential pair.
    It is not sensitive on its own — authentication requires BOTH role_id
    and secret_id. However, treat it with care: exposing role_id reduces
    the credentials to a single-factor (secret_id only).
    Stored in KV by the kv_secret module in root/main.tf.
  EOD
  value = vault_approle_auth_backend_role.this.role_id
}

output "secret_id" {
  description = <<-EOD
    The bootstrap secret_id for this AppRole. SENSITIVE.
    Generated at role creation time by Terraform.
    Stored in Terraform state (must be encrypted) and written to KV.
    Applications MUST rotate this immediately after first use:
      POST /v1/auth/approle/role/<role_name>/secret-id
    with a token that has the nwpci-self-secret-id policy.
  EOD
  sensitive = true
  value     = vault_approle_auth_backend_role_secret_id.this.secret_id
}

output "secret_id_accessor" {
  description = <<-EOD
    The accessor for the bootstrap secret_id. NOT sensitive.
    An accessor uniquely identifies a secret_id without revealing its value.
    Use the accessor to revoke the bootstrap credential after rotation:
      vault write auth/approle/role/<role>/secret-id-accessor/destroy \
        secret_id_accessor=<accessor>
    Also appears in Vault audit logs alongside login events, enabling
    correlation of authentication events to specific secret_id issuances.
  EOD
  value = vault_approle_auth_backend_role_secret_id.this.accessor
}

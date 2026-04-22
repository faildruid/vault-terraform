###############################################################################
# outputs.tf — Root outputs
#
# Outputs expose resource attributes for:
#   1. Human operators inspecting state after apply
#   2. External automation consuming role_ids / secret_ids for bootstrap
#   3. Downstream Terraform configurations referencing this module's outputs
#
# Sensitive outputs are marked sensitive=true.
# They are redacted in console output but still accessible via:
#   terraform output -json <output_name>
#   terraform output -raw <output_name>   (single string values)
#
# WARNING: terraform output -json exposes all sensitive values in plaintext.
# Restrict who can run that command in shared environments.
# Pipe output to a secrets manager rather than logging it.
###############################################################################

# Engine mount paths — useful for confirming which paths were created
# and for referencing in downstream Terraform configurations.
output "kv_engine_mount_paths" {
  description = "Map of KV v2 engine names to their Vault mount paths."
  value = {
    atm      = module.kv_engine_atm.mount_path
    data     = module.kv_engine_data.mount_path
    lb       = module.kv_engine_lb.mount_path
    security = module.kv_engine_security.mount_path
  }
}

# role_id values for all eight AppRoles.
# role_id is not sensitive by Vault's security model (it is the "username"
# half of the credential pair) but should still be treated carefully —
# it cannot be used alone to authenticate without the secret_id.
output "approle_role_ids" {
  description = <<-EOD
    AppRole role_id values keyed by a short role label.
    role_id is the stable identifier for an AppRole role.
    It does not change unless the role is deleted and re-created.
    Provide this to consuming applications alongside the secret_id.
  EOD
  value = {
    nwpci_awx_nwauto = module.approle_nwpci_awx_nwauto.role_id
    nwpci_awx_nwdata = module.approle_nwpci_awx_nwdata.role_id
    nwpci_awx_nwlb   = module.approle_nwpci_awx_nwlb.role_id
    nwpci_awx_nwsec  = module.approle_nwpci_awx_nwsec.role_id
    nwpci_sms_nwauto = module.approle_nwpci_sms_nwauto.role_id
    nwpci_sms_nwdata = module.approle_nwpci_sms_nwdata.role_id
    nwpci_sms_lb     = module.approle_nwpci_sms_lb.role_id
    nwpci_sms_nwsec  = module.approle_nwpci_sms_nwsec.role_id
  }
}

# secret_id values — marked sensitive.
# These are the bootstrap secret_ids generated at creation time.
# They are stored in Terraform state (encrypted at rest in remote backends).
# Applications MUST rotate the secret_id after first use using the
# nwpci-self-secret-id policy attached to each role.
output "approle_secret_ids" {
  description = <<-EOD
    Bootstrap secret_id values for all AppRoles. SENSITIVE.
    These are one-time bootstrap credentials — rotate immediately after use.
    Retrieve with: terraform output -json approle_secret_ids
    Do NOT log this output. Pipe it directly into a secrets manager.
  EOD
  sensitive = true
  value = {
    nwpci_awx_nwauto = module.approle_nwpci_awx_nwauto.secret_id
    nwpci_awx_nwdata = module.approle_nwpci_awx_nwdata.secret_id
    nwpci_awx_nwlb   = module.approle_nwpci_awx_nwlb.secret_id
    nwpci_awx_nwsec  = module.approle_nwpci_awx_nwsec.secret_id
    nwpci_sms_nwauto = module.approle_nwpci_sms_nwauto.secret_id
    nwpci_sms_nwdata = module.approle_nwpci_sms_nwdata.secret_id
    nwpci_sms_lb     = module.approle_nwpci_sms_lb.secret_id
    nwpci_sms_nwsec  = module.approle_nwpci_sms_nwsec.secret_id
  }
}

# secret_id accessors — NOT sensitive.
# An accessor uniquely identifies a secret_id without revealing its value.
# Use accessors to revoke a specific secret_id via:
#   vault write auth/approle/role/<role>/secret-id-accessor/destroy \
#     secret_id_accessor=<accessor>
output "approle_secret_id_accessors" {
  description = <<-EOD
    secret_id accessor values for all AppRoles.
    Accessors are used to revoke a specific secret_id without needing
    the secret_id itself. Useful for audit, incident response, and
    rotation workflows that need to invalidate the old credential.
  EOD
  value = {
    nwpci_awx_nwauto = module.approle_nwpci_awx_nwauto.secret_id_accessor
    nwpci_awx_nwdata = module.approle_nwpci_awx_nwdata.secret_id_accessor
    nwpci_awx_nwlb   = module.approle_nwpci_awx_nwlb.secret_id_accessor
    nwpci_awx_nwsec  = module.approle_nwpci_awx_nwsec.secret_id_accessor
    nwpci_sms_nwauto = module.approle_nwpci_sms_nwauto.secret_id_accessor
    nwpci_sms_nwdata = module.approle_nwpci_sms_nwdata.secret_id_accessor
    nwpci_sms_lb     = module.approle_nwpci_sms_lb.secret_id_accessor
    nwpci_sms_nwsec  = module.approle_nwpci_sms_nwsec.secret_id_accessor
  }
}

# All policy names — useful for confirming policy creation and for
# referencing in external Vault configuration outside this project.
output "policy_names" {
  description = "Map of all Vault policies created by this configuration."
  value       = module.policies.all_policy_names
}

# KV paths where AppRole credentials are stored.
# Consuming applications or operators can look up credentials at these paths
# using a Vault token with appropriate read permissions.
output "kv_credential_paths" {
  description = <<-EOD
    KV v2 paths (including mount prefix) where AppRole credentials are stored.
    Format: <mount>/data/<path>
    Read with: vault kv get <mount>/<path>  (vault CLI strips /data/ automatically)
    Or via API: GET /v1/<mount>/data/<path>
  EOD
  value = {
    sms_nwauto = module.kv_creds_sms_nwauto.full_secret_path
    sms_nwdata = module.kv_creds_sms_nwdata.full_secret_path
    sms_lb     = module.kv_creds_sms_lb.full_secret_path
    sms_nwsec  = module.kv_creds_sms_nwsec.full_secret_path
    awx_nwauto = module.kv_creds_awx_nwauto.full_secret_path
    awx_nwdata = module.kv_creds_awx_nwdata.full_secret_path
    awx_nwlb   = module.kv_creds_awx_nwlb.full_secret_path
    awx_nwsec  = module.kv_creds_awx_nwsec.full_secret_path
  }
}

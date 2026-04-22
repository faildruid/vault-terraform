###############################################################################
# modules/policy/outputs.tf
#
# Exposes policy names for consumption by the approle module.
# The approle module attaches policies by name — outputting names here
# avoids hardcoding them in the root module's approle invocations.
###############################################################################

# Individual policy name outputs — used by root/main.tf to attach
# the correct policies to each AppRole without string duplication.

output "policy_name_self_secret_id" {
  description = "Name of the self secret_id rotation policy attached to all roles."
  value       = vault_policy.self_secret_id.name
}

output "policy_name_awx_nwauto" {
  description = "Policy name for nwpci-awx-nwauto (read/list on network-atm-secrets)."
  value       = vault_policy.awx_nwauto_ro.name
}

output "policy_name_sms_nwauto" {
  description = "Policy name for nwpci-sms-nwauto (full access on network-atm-secrets)."
  value       = vault_policy.sms_nwauto_rw.name
}

output "policy_name_awx_nwdata" {
  description = "Policy name for nwpci-awx-nwdata (read/list on network-data-secrets)."
  value       = vault_policy.awx_nwdata_ro.name
}

output "policy_name_sms_nwdata" {
  description = "Policy name for nwpci-sms-nwdata (full access on network-data-secrets)."
  value       = vault_policy.sms_nwdata_rw.name
}

output "policy_name_awx_nwlb" {
  description = "Policy name for nwpci-awx-nwlb (read/list on network-lb-secrets)."
  value       = vault_policy.awx_nwlb_ro.name
}

output "policy_name_sms_nwlb" {
  description = "Policy name for nwpci-sms-lb (full access on network-lb-secrets)."
  value       = vault_policy.sms_nwlb_rw.name
}

output "policy_name_awx_nwsec" {
  description = "Policy name for nwpci-awx-nwsec (read/list on network-security-secrets)."
  value       = vault_policy.awx_nwsec_ro.name
}

output "policy_name_sms_nwsec" {
  description = "Policy name for nwpci-sms-nwsec (full access on network-security-secrets)."
  value       = vault_policy.sms_nwsec_rw.name
}

# Aggregate output — useful for displaying all policy names in root outputs
# and for downstream configurations that need the complete list.
output "all_policy_names" {
  description = "Map of all policy names created by this module, keyed by a short label."
  value = {
    self_secret_id = vault_policy.self_secret_id.name
    awx_nwauto_ro  = vault_policy.awx_nwauto_ro.name
    sms_nwauto_rw  = vault_policy.sms_nwauto_rw.name
    awx_nwdata_ro  = vault_policy.awx_nwdata_ro.name
    sms_nwdata_rw  = vault_policy.sms_nwdata_rw.name
    awx_nwlb_ro    = vault_policy.awx_nwlb_ro.name
    sms_nwlb_rw    = vault_policy.sms_nwlb_rw.name
    awx_nwsec_ro   = vault_policy.awx_nwsec_ro.name
    sms_nwsec_rw   = vault_policy.sms_nwsec_rw.name
  }
}

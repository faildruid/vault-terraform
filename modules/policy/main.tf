###############################################################################
# modules/policy/main.tf
#
# Creates all Vault HCL policies governing access to the four KV engines.
#
# Policy naming convention: nwpci-<consumer>-<domain>-<level>
#   consumer:  awx (Ansible AWX) | sms (Secret Management Service) | self
#   domain:    nwauto | nwdata | nwlb | nwsec
#   level:     ro (read/list) | rw (full access)
#
# Special policy: nwpci-self-secret-id
#   Attached to all eight roles. Allows each role to rotate its own
#   secret_id without operator intervention. Uses a + wildcard so the
#   same policy text applies to any role name.
#
# Template-driven policy generation:
#   Rather than duplicating policy HCL for each engine×level combination,
#   two .tftpl template files parameterise the mount path. This ensures
#   every engine gets exactly the same capability set and eliminates the
#   risk of inconsistency from manual copy-paste.
#
#   templates/kv_read_list.tftpl  → read + list (AWX consumers)
#   templates/kv_full_access.tftpl → full CRUD (SMS owners)
#
# KV v2 path structure (enforced in policies):
#   <mount>/data/<path>      — secret payload (read/write)
#   <mount>/metadata/<path>  — version metadata + custom_metadata
#   <mount>/delete/<path>    — soft-delete specific versions
#   <mount>/undelete/<path>  — recover soft-deleted versions
#   <mount>/destroy/<path>   — permanent hard-delete
#   <mount>/subkeys/<path>   — list key names without values
#   <mount>/config           — engine-level configuration
#
# All path capabilities follow the principle of least privilege:
#   AWX (ro): read + list only — cannot modify any secret or metadata
#   SMS (rw): full CRUD — can create, update, delete secrets and metadata
###############################################################################

# ---------------------------------------------------------------------------
# nwpci-self-secret-id
#
# Purpose: allow any AppRole to generate a new secret_id for itself after login.
#
# Mechanism: when an AppRole logs in, the resulting service token has this
# policy attached. The + wildcard matches any role name segment, so the
# same policy applies regardless of which role issued the token.
#
# Security consideration: the + wildcard technically grants any token holding
# this policy the ability to generate a secret_id for ANY role, not just its
# own. In practice this is constrained because:
#   1. A token can only be obtained by a successful AppRole login.
#   2. Each role's token_policies list is fixed at role creation time.
#   3. A token cannot elevate its own policies.
# However, if you require strict per-role isolation, replace + with the
# literal role name and create one self-rotation policy per role.
# ---------------------------------------------------------------------------
resource "vault_policy" "self_secret_id" {
  name = "nwpci-self-secret-id"

  policy = <<-EOT
    # Generate a new secret_id for any AppRole role.
    # Used for self-service credential rotation — the application calls this
    # endpoint with its current token to get a fresh secret_id before the
    # old one expires or is revoked.
    path "auth/approle/role/+/secret-id" {
      capabilities = ["create", "update"]
    }

    # Read the role_id for any AppRole role.
    # Required so the application can confirm its own role_id at startup
    # without needing a separate operator-managed token.
    path "auth/approle/role/+/role-id" {
      capabilities = ["read"]
    }
  EOT
}

# ---------------------------------------------------------------------------
# network-atm-secrets — AWX consumer (read/list)
# Attached to: nwpci-awx-nwauto
# ---------------------------------------------------------------------------
resource "vault_policy" "awx_nwauto_ro" {
  name   = "nwpci-awx-nwauto-ro"
  policy = templatefile("${path.module}/templates/kv_read_list.tftpl", { mount = var.atm_mount })
}

# ---------------------------------------------------------------------------
# network-atm-secrets — SMS owner (full access)
# Attached to: nwpci-sms-nwauto
# ---------------------------------------------------------------------------
resource "vault_policy" "sms_nwauto_rw" {
  name   = "nwpci-sms-nwauto-rw"
  policy = templatefile("${path.module}/templates/kv_full_access.tftpl", { mount = var.atm_mount })
}

# ---------------------------------------------------------------------------
# network-data-secrets — AWX consumer (read/list)
# Attached to: nwpci-awx-nwdata
# ---------------------------------------------------------------------------
resource "vault_policy" "awx_nwdata_ro" {
  name   = "nwpci-awx-nwdata-ro"
  policy = templatefile("${path.module}/templates/kv_read_list.tftpl", { mount = var.data_mount })
}

# ---------------------------------------------------------------------------
# network-data-secrets — SMS owner (full access)
# Attached to: nwpci-sms-nwdata
# ---------------------------------------------------------------------------
resource "vault_policy" "sms_nwdata_rw" {
  name   = "nwpci-sms-nwdata-rw"
  policy = templatefile("${path.module}/templates/kv_full_access.tftpl", { mount = var.data_mount })
}

# ---------------------------------------------------------------------------
# network-lb-secrets — AWX consumer (read/list)
# Attached to: nwpci-awx-nwlb
# ---------------------------------------------------------------------------
resource "vault_policy" "awx_nwlb_ro" {
  name   = "nwpci-awx-nwlb-ro"
  policy = templatefile("${path.module}/templates/kv_read_list.tftpl", { mount = var.lb_mount })
}

# ---------------------------------------------------------------------------
# network-lb-secrets — SMS owner (full access)
# Attached to: nwpci-sms-lb
# ---------------------------------------------------------------------------
resource "vault_policy" "sms_nwlb_rw" {
  name   = "nwpci-sms-nwlb-rw"
  policy = templatefile("${path.module}/templates/kv_full_access.tftpl", { mount = var.lb_mount })
}

# ---------------------------------------------------------------------------
# network-security-secrets — AWX consumer (read/list)
# Attached to: nwpci-awx-nwsec
# ---------------------------------------------------------------------------
resource "vault_policy" "awx_nwsec_ro" {
  name   = "nwpci-awx-nwsec-ro"
  policy = templatefile("${path.module}/templates/kv_read_list.tftpl", { mount = var.security_mount })
}

# ---------------------------------------------------------------------------
# network-security-secrets — SMS owner (full access)
# Attached to: nwpci-sms-nwsec
# ---------------------------------------------------------------------------
resource "vault_policy" "sms_nwsec_rw" {
  name   = "nwpci-sms-nwsec-rw"
  policy = templatefile("${path.module}/templates/kv_full_access.tftpl", { mount = var.security_mount })
}

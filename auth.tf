###############################################################################
# auth.tf — Vault auth backend registration
#
# Auth backends are cluster-global resources. Enabling the same backend twice
# at the same path causes a Terraform error. This file enables AppRole once at
# the root level.
#
# All approle module instances reference the backend via a data source
# (modules/approle/auth_backend.tf) rather than managing it themselves.
# This avoids the resource conflict that would occur if each module instance
# tried to create the same vault_auth_backend resource.
#
# Dependency order:
#   vault_auth_backend.approle must exist before any
#   vault_approle_auth_backend_role resource is created.
#   This is enforced implicitly: approle modules use
#   depends_on = [data.vault_auth_backend.approle] which resolves after this
#   resource is created.
###############################################################################

resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "AppRole auth for network PCI automation (AWX + SMS consumers)"

  tune {
    # Default token TTL applied to all roles unless overridden at the role level.
    # Role-level token_ttl takes precedence over this mount-level default.
    default_lease_ttl = "1h"

    # Hard ceiling on token lifetime. No token issued from this mount can
    # exceed this TTL, regardless of role-level token_max_ttl settings.
    max_lease_ttl = "4h"

    # "default-service" issues regular service tokens.
    # Switch to "batch" at the mount level only if ALL roles should issue
    # batch tokens — batch tokens cannot be revoked individually.
    token_type = "default-service"
  }
}

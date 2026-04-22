###############################################################################
# modules/approle/auth_backend.tf
#
# Data source lookup for the AppRole auth backend.
#
# The vault_auth_backend resource is created ONCE in root/auth.tf.
# This module is instantiated eight times (once per AppRole role).
# If each instance declared a vault_auth_backend resource, Terraform would
# attempt to create the same resource eight times, causing a conflict error
# on the second through eighth instantiation.
#
# Solution: use a data source to READ the existing backend rather than
# managing it. The data source succeeds as long as the backend exists
# (guaranteed by root/auth.tf's resource running first).
#
# The data source is also referenced in depends_on in main.tf to make the
# dependency explicit — vault_approle_auth_backend_role cannot be created
# before its backend exists.
###############################################################################

data "vault_auth_backend" "approle" {
  # Path must match the path used in root/auth.tf vault_auth_backend.approle.
  # If the auth backend is mounted at a non-default path, update both this
  # file and the resource in root/auth.tf to match.
  path = "approle"
}

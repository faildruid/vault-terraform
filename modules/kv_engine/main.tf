###############################################################################
# modules/kv_engine/main.tf
#
# Mounts a single KV v2 secret engine and configures its backend settings.
#
# Two resources are created per invocation:
#
#   vault_mount — registers the engine at a path in Vault's mount table.
#     This is the top-level path segment used in all API calls and policies.
#     Example: mount_path = "network-atm-secrets" registers the engine at
#     /v1/network-atm-secrets/...
#
#   vault_kv_secret_backend_v2 — configures the KV v2 specific settings
#     for the mounted engine (max_versions, CAS, delete_version_after).
#     This maps to a POST /v1/<mount>/config call on the Vault API.
#
# KV v2 vs KV v1:
#   KV v2 is always used here. It provides:
#     - Secret versioning (up to max_versions copies of each secret)
#     - Soft delete (secrets can be undeleted within the retention window)
#     - Metadata API (/metadata/<path>) separate from data API (/data/<path>)
#     - Custom metadata (arbitrary key/value attached to secret paths)
#   KV v1 has none of these features and should not be used for new mounts.
###############################################################################

resource "vault_mount" "this" {
  path        = var.mount_path
  type        = "kv"
  description = var.description

  # options.version = "2" activates KV v2 mode.
  # This cannot be changed after mount creation without re-mounting.
  options = {
    version = "2"
  }

  # default_lease_ttl_seconds: default TTL for dynamic secrets.
  # KV v2 does not issue leases for static secrets, so this value has no
  # practical effect on stored secrets. It is set for completeness and to
  # ensure consistent behaviour if the mount type is later changed.
  default_lease_ttl_seconds = 3600 # 1 hour

  # max_lease_ttl_seconds: hard ceiling on lease duration for this mount.
  # Same caveat as above — set for hygiene and forward compatibility.
  max_lease_ttl_seconds = 86400 # 24 hours

  # seal_wrap: when true, Vault uses the configured seal (HSM, AWS KMS, etc.)
  # to additionally encrypt values stored at this mount, providing an extra
  # layer of protection beyond Vault's internal encryption.
  # Enable in production when a cloud KMS or HSM seal is configured.
  # Requires Vault Enterprise for transit/unseal key separation.
  # seal_wrap = true
}

resource "vault_kv_secret_backend_v2" "this" {
  mount = vault_mount.this.path

  # max_versions: number of secret versions retained per path.
  # Older versions beyond this count are automatically deleted.
  # 10 versions provides sufficient audit history without excessive storage.
  max_versions = 10

  # delete_version_after: duration after which a soft-deleted version is
  # permanently destroyed. "0s" means deleted versions are never automatically
  # purged — they remain recoverable until explicitly destroyed.
  # Set a duration (e.g. "720h" = 30 days) in high-churn environments
  # to avoid unbounded storage growth.
  delete_version_after = "0s"

  # cas_required: when true, all write operations must supply a
  # check-and-set (CAS) parameter matching the current version number.
  # This prevents lost updates in concurrent write scenarios.
  # Disable here for simplicity; enable for secrets that must not be
  # overwritten accidentally (e.g. CA certificates, signing keys).
  cas_required = false

  # vault_mount.this must exist before vault_kv_secret_backend_v2 can be
  # configured — Terraform infers this from the mount reference above,
  # but the explicit depends_on makes the intent clear.
  depends_on = [vault_mount.this]
}

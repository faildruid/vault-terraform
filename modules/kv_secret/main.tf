###############################################################################
# modules/kv_secret/main.tf
#
# Writes a single KV v2 secret containing AppRole credentials (role_id +
# secret_id) and attaches custom metadata to the secret path.
#
# Used exclusively for storing AppRole bootstrap credentials in KV.
# Sample device secrets are written directly as vault_kv_secret_v2 resources
# in root/main.tf using a for_each loop (they have a different payload schema).
#
# KV v2 write model:
#   Calling vault_kv_secret_v2 creates a new VERSION of the secret at the
#   given path. Existing versions are preserved up to max_versions (set at
#   the engine level in the kv_engine module).
#   Each terraform apply that changes data_json creates a new version.
#
# Custom metadata vs secret data:
#   data_json  — the secret payload, versioned (new version per write)
#   custom_metadata.data — key/value attached to the PATH, NOT versioned
#     Metadata updates do NOT increment the secret version.
#     Metadata persists across secret version changes.
#     All versions of a secret share the same metadata.
#
# Secret payload schema:
#   {
#     "role_id":   "<vault-assigned UUID>",
#     "secret_id": "<vault-assigned UUID>"
#   }
#
# Custom metadata schema:
#   expiry_date         — ISO 8601 date for rotation scheduling
#   pwd_rotation_data   — JSON string encoding the rotation context
#   pwd_rotation_method — "auto" | "manual"
#   approle_name        — human-readable role name for UI browsing
#   environment         — environment label (dev | staging | prod)
###############################################################################

resource "vault_kv_secret_v2" "this" {
  mount = var.mount_path

  # name is the path within the mount, without leading slash.
  # KV v2 stores this under <mount>/data/<name> internally.
  # The Vault CLI and UI strip the /data/ prefix automatically.
  name = var.secret_path

  # delete_all_versions = false means terraform destroy will only mark the
  # latest version as deleted (soft delete) rather than permanently destroying
  # all versions. Set to true if you want hard-delete on destroy.
  delete_all_versions = false

  # data_json must be a JSON-encoded string.
  # jsonencode produces canonical JSON — deterministic key ordering prevents
  # spurious diffs on terraform plan when nothing has actually changed.
  # secret_id is marked sensitive in the variable; its value will be redacted
  # in plan output but the jsonencode call itself cannot be marked sensitive,
  # so the composed JSON string may appear in debug logs. Treat with care.
  data_json = jsonencode({
    role_id   = var.role_id
    secret_id = var.secret_id
  })

  custom_metadata {
    # max_versions here overrides the engine-level default for this specific
    # secret path. Setting it explicitly ensures consistent version retention
    # regardless of future changes to the engine-level default.
    max_versions = 10

    # data is a map(string) — all values must be strings.
    # Complex values (like pwd_rotation_data) are JSON-encoded to a string
    # before being stored. Consumers must JSON-decode that field when reading.
    data = var.custom_metadata
  }
}

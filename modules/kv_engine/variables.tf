###############################################################################
# modules/kv_engine/variables.tf
###############################################################################

variable "mount_path" {
  description = <<-EOD
    Path at which to mount the KV v2 engine in Vault's mount table.
    This becomes the first path segment in all API calls to this engine.
    Example: "network-atm-secrets" → all secrets accessible at
    /v1/network-atm-secrets/data/<path>
    Must be unique across all mount paths in the Vault cluster.
    Cannot be changed after creation without destroying and re-creating.
  EOD
  type = string
}

variable "description" {
  description = <<-EOD
    Human-readable description displayed in the Vault UI and returned by
    GET /v1/sys/mounts. Used for operator reference only — has no functional
    effect on the engine's behaviour.
  EOD
  type    = string
  default = ""
}

variable "environment" {
  description = <<-EOD
    Deployment environment label (dev | staging | prod).
    Passed in from the root module for consistency but not used functionally
    in this module — the mount path itself encodes the domain, not the env.
    Retained for future use (e.g. adding environment tags if Vault namespaces
    support tagging in a future provider version).
  EOD
  type = string
}

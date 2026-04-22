###############################################################################
# modules/kv_engine/outputs.tf
###############################################################################

output "mount_path" {
  description = <<-EOD
    The path at which the KV v2 engine is mounted.
    Use this output to reference the mount in policies and secret paths
    rather than hardcoding the string, so renaming a mount only requires
    changing the module's mount_path variable.
  EOD
  value = vault_mount.this.path
}

output "accessor" {
  description = <<-EOD
    The mount accessor assigned by Vault when the engine is mounted.
    Accessors uniquely identify a mount across path renames and are used:
      - In Vault audit log entries to identify the originating mount.
      - In identity group policies to scope access to a specific mount
        instance rather than a path (path can be renamed; accessor cannot).
    Useful for advanced policy and identity configurations.
  EOD
  value = vault_mount.this.accessor
}

###############################################################################
# modules/policy/variables.tf
###############################################################################

variable "environment" {
  description = <<-EOD
    Deployment environment label. Passed through from root for consistency.
    Not currently used in policy HCL but available for future environment-
    scoped policies (e.g. restricting access to paths containing the env name).
  EOD
  type = string
}

variable "atm_mount" {
  description = <<-EOD
    Mount path of the network-atm-secrets KV v2 engine.
    Injected into policy templates so policies reference the correct path.
    Sourced from module.kv_engine_atm.mount_path in the root module.
    Using a variable (rather than a hardcoded string) means renaming the
    engine only requires changing the kv_engine module's mount_path variable.
  EOD
  type = string
}

variable "data_mount" {
  description = <<-EOD
    Mount path of the network-data-secrets KV v2 engine.
    See atm_mount description for rationale.
  EOD
  type = string
}

variable "lb_mount" {
  description = <<-EOD
    Mount path of the network-lb-secrets KV v2 engine.
    See atm_mount description for rationale.
  EOD
  type = string
}

variable "security_mount" {
  description = <<-EOD
    Mount path of the network-security-secrets KV v2 engine.
    See atm_mount description for rationale.
  EOD
  type = string
}

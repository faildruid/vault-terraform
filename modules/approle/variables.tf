###############################################################################
# modules/approle/variables.tf
###############################################################################

variable "role_name" {
  description = <<-EOD
    AppRole role name. Must be unique within the Vault AppRole auth backend.
    Naming convention: nwpci-<consumer>-<domain>
      consumer: awx (Ansible AWX) | sms (Secret Management Service)
      domain:   nwauto | nwdata | nwlb (lb for SMS) | nwsec
    Examples: nwpci-awx-nwauto, nwpci-sms-lb
    Cannot be changed after creation without destroying and re-creating the role.
    Changing the name invalidates all existing role_id and secret_id values.
  EOD
  type = string
}

variable "policy_names" {
  description = <<-EOD
    Ordered list of Vault policy names to attach to tokens issued by this role.
    Vault evaluates multiple policies as a union — the token receives the
    maximum capability set across all listed policies.
    Minimum two policies per role:
      [0] nwpci-self-secret-id  — self rotation capability
      [1] nwpci-<consumer>-<domain>-<ro|rw>  — domain access
    Policy names are sourced from module.policies outputs in root/main.tf
    to avoid hardcoding strings.
  EOD
  type = list(string)
}

variable "token_ttl" {
  description = <<-EOD
    Time-to-live for tokens issued on AppRole login.
    Vault will not automatically renew a token past this duration.
    Applications should call token renewal (POST /v1/auth/token/renew-self)
    before this elapses, or re-authenticate to get a fresh token.
    Format: Vault duration string — "1h", "30m", "3600s".
    Shorter TTLs reduce blast radius from leaked tokens.
    Must be <= token_max_ttl.
  EOD
  type    = string
  default = "1h"
}

variable "token_max_ttl" {
  description = <<-EOD
    Maximum lifetime for tokens issued by this role, including renewals.
    A token cannot be renewed beyond this duration from its creation time.
    After this elapses, the application must call AppRole login again.
    Format: Vault duration string — "4h", "8h".
    Must be >= token_ttl.
  EOD
  type    = string
  default = "4h"
}

variable "secret_id_num_uses" {
  description = <<-EOD
    Number of times a single secret_id can be used to authenticate before
    Vault automatically invalidates it.
    0  = unlimited uses (suitable for persistent daemons, long-running services)
    1  = single use   (highest security, suitable for CI jobs, one-shot tasks)
    >1 = fixed count  (intermediate — use when a service restarts N times/day)
    For production environments with automated rotation, prefer 1 and use
    the nwpci-self-secret-id policy to generate a fresh secret_id per job run.
  EOD
  type    = number
  default = 0
}

variable "secret_id_ttl" {
  description = <<-EOD
    Duration a generated secret_id remains valid after creation.
    "0" = no expiry (secret_id valid indefinitely until used or revoked)
    Setting a finite TTL (e.g. "720h" = 30 days) provides a safety net:
    if rotation tooling fails, stale credentials auto-expire rather than
    persisting indefinitely.
    Format: Vault duration string — "0", "720h", "168h".
  EOD
  type    = string
  default = "0"
}

variable "bind_secret_id_cidr_list" {
  description = <<-EOD
    Optional list of CIDR blocks restricting secret_id usage by source IP.
    When set, Vault rejects AppRole login attempts from IPs outside these ranges
    even if role_id and secret_id are valid.
    Use to lock credentials to known automation infrastructure IP ranges.
    Example: ["10.0.1.0/24", "10.0.2.50/32"]
    Empty list = no CIDR restriction (default).
  EOD
  type    = list(string)
  default = []
}

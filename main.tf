###############################################################################
# main.tf — Root configuration
#
# Entry point for all Vault resource provisioning. This file instantiates
# every module in dependency order:
#
#   1. kv_engine  — mount four KV v2 secret engines
#   2. policy     — create all HCL policies (depends on engine mounts existing)
#   3. approle    — create eight AppRole auth roles (depends on policies)
#   4. kv_secret  — store AppRole credentials in KV (depends on approles)
#   5. locals/resource — write sample device secrets into each engine
#
# Dependency chain (enforced by depends_on and implicit references):
#   kv_engine → policy → approle → kv_secret
#
# Provider version constraint ~> 4.4.0 allows patch upgrades but locks the
# minor version. The hashicorp/vault provider maps 1:1 to the Vault HTTP API;
# upgrading minor versions may introduce new resource attributes or deprecate
# old ones — pin deliberately and test before upgrading.
#
# Remote state backend is commented out. Uncomment the backend "s3" block and
# supply environments/<env>/backend.hcl when enabling remote state.
# Local state is acceptable for development only.
###############################################################################

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.4.0"
    }
  }

  # ---------------------------------------------------------------------------
  # Remote state backend (S3 + DynamoDB locking)
  # Uncomment and configure before running in any shared environment.
  # Pass per-environment values via: terraform init -backend-config=environments/<env>/backend.hcl
  # ---------------------------------------------------------------------------
  # backend "s3" {
  #   bucket         = "tfstate-vault-config"
  #   key            = "vault/network-pci/terraform.tfstate"
  #   region         = "eu-west-1"
  #   encrypt        = true          # AES-256 server-side encryption
  #   dynamodb_table = "tfstate-lock" # Prevents concurrent apply races
  # }
}

###############################################################################
# Provider
#
# The vault provider authenticates using VAULT_TOKEN from the environment.
# In CI pipelines, obtain a short-lived token via:
#   export VAULT_TOKEN=$(vault write -field=token auth/approle/login \
#     role_id=$CI_ROLE_ID secret_id=$CI_SECRET_ID)
#
# For human operators, use: vault login -method=oidc
#
# Do NOT hardcode tokens in this file or in tfvars.
###############################################################################

provider "vault" {
  address = var.vault_address
  # VAULT_TOKEN is read from the environment automatically.
  # Alternatively use an auth_login block for OIDC or cert-based auth:
  # auth_login_oidc { role = "terraform" }
}

###############################################################################
# KV Secret Engines
#
# Four KV v2 engines are mounted, one per network domain.
# Separation by mount provides independent:
#   - Policy scope: a policy grants access to paths under ONE mount only.
#   - Audit trails: each mount appears distinctly in Vault audit logs.
#   - Access controls: operators can manage each engine independently.
#
# All mounts are managed by the kv_engine module which applies consistent
# configuration (max_versions=10, lease TTLs, KV v2 backend settings).
###############################################################################

# ATM / automation network secrets
# Holds: device credentials for ATM-connected network equipment.
# Also used as the credential store for ALL AppRole credentials (SMS + AWX).
module "kv_engine_atm" {
  source      = "./modules/kv_engine"
  mount_path  = "network-atm-secrets"
  description = "KV v2 engine for network ATM secrets"
  environment = var.environment
}

# Data network device secrets
# Holds: credentials for switches, routers, and data-plane network devices.
module "kv_engine_data" {
  source      = "./modules/kv_engine"
  mount_path  = "network-data-secrets"
  description = "KV v2 engine for network data secrets"
  environment = var.environment
}

# Load balancer secrets
# Holds: credentials for F5, NGINX, HAProxy, and other LB platforms.
module "kv_engine_lb" {
  source      = "./modules/kv_engine"
  mount_path  = "network-lb-secrets"
  description = "KV v2 engine for network load balancer secrets"
  environment = var.environment
}

# Security device secrets
# Holds: credentials for firewalls, IDS/IPS, and security appliances.
module "kv_engine_security" {
  source      = "./modules/kv_engine"
  mount_path  = "network-security-secrets"
  description = "KV v2 engine for network security secrets"
  environment = var.environment
}

###############################################################################
# Policies
#
# All nine policies are managed in the policy module.
# The module receives the engine mount paths as variables so policy HCL
# references the correct paths — no hardcoded strings in policy HCL.
#
# Policy matrix:
#   nwpci-self-secret-id   → attached to all 8 roles; allows self secret_id rotation
#   nwpci-awx-nwauto-ro    → attached to nwpci-awx-nwauto; read/list network-atm-secrets
#   nwpci-sms-nwauto-rw    → attached to nwpci-sms-nwauto; full access network-atm-secrets
#   nwpci-awx-nwdata-ro    → attached to nwpci-awx-nwdata; read/list network-data-secrets
#   nwpci-sms-nwdata-rw    → attached to nwpci-sms-nwdata; full access network-data-secrets
#   nwpci-awx-nwlb-ro      → attached to nwpci-awx-nwlb;   read/list network-lb-secrets
#   nwpci-sms-nwlb-rw      → attached to nwpci-sms-lb;     full access network-lb-secrets
#   nwpci-awx-nwsec-ro     → attached to nwpci-awx-nwsec;  read/list network-security-secrets
#   nwpci-sms-nwsec-rw     → attached to nwpci-sms-nwsec;  full access network-security-secrets
#
# depends_on is explicit here because the policy HCL contains mount path strings.
# If the engines have not been mounted yet, a terraform plan would still succeed
# but an apply would fail on the policy write as Vault validates paths.
###############################################################################

module "policies" {
  source = "./modules/policy"

  environment = var.environment

  # Engine mount paths are passed explicitly so policy HCL is generated
  # correctly without hardcoding path strings in the module itself.
  atm_mount      = module.kv_engine_atm.mount_path
  data_mount     = module.kv_engine_data.mount_path
  lb_mount       = module.kv_engine_lb.mount_path
  security_mount = module.kv_engine_security.mount_path

  depends_on = [
    module.kv_engine_atm,
    module.kv_engine_data,
    module.kv_engine_lb,
    module.kv_engine_security,
  ]
}

###############################################################################
# AppRoles
#
# Eight AppRole roles are created, one per consumer×domain combination.
# Naming convention: nwpci-<consumer>-<domain>
#   consumer: awx (Ansible AWX automation) | sms (Secret Management Service)
#   domain:   nwauto | nwdata | nwlb (lb for SMS) | nwsec
#
# Each role is attached two policies:
#   1. nwpci-self-secret-id — allows the role to rotate its own secret_id
#   2. A domain-specific policy (ro for AWX, rw for SMS)
#
# Token TTLs are controlled by var.approle_token_ttl and var.approle_token_max_ttl.
# These are deliberately short (default 1h/4h) to limit blast radius if a
# token is leaked. Applications should re-authenticate before token expiry.
#
# Each module instance also generates a bootstrap secret_id (stored in state
# and in KV — see kv_creds_* modules below). This secret_id is for initial
# provisioning only. Applications must rotate it immediately after first use
# by calling POST /v1/auth/approle/role/<role>/secret-id with their token.
###############################################################################

# AWX consumer — network-atm-secrets — read/list only
module "approle_nwpci_awx_nwauto" {
  source    = "./modules/approle"
  role_name = "nwpci-awx-nwauto"
  policy_names = [
    module.policies.policy_name_self_secret_id, # self rotation
    module.policies.policy_name_awx_nwauto,     # read/list on network-atm-secrets
  ]
  token_ttl     = var.approle_token_ttl
  token_max_ttl = var.approle_token_max_ttl
  depends_on    = [module.policies]
}

# AWX consumer — network-data-secrets — read/list only
module "approle_nwpci_awx_nwdata" {
  source    = "./modules/approle"
  role_name = "nwpci-awx-nwdata"
  policy_names = [
    module.policies.policy_name_self_secret_id,
    module.policies.policy_name_awx_nwdata, # read/list on network-data-secrets
  ]
  token_ttl     = var.approle_token_ttl
  token_max_ttl = var.approle_token_max_ttl
  depends_on    = [module.policies]
}

# AWX consumer — network-lb-secrets — read/list only
module "approle_nwpci_awx_nwlb" {
  source    = "./modules/approle"
  role_name = "nwpci-awx-nwlb"
  policy_names = [
    module.policies.policy_name_self_secret_id,
    module.policies.policy_name_awx_nwlb, # read/list on network-lb-secrets
  ]
  token_ttl     = var.approle_token_ttl
  token_max_ttl = var.approle_token_max_ttl
  depends_on    = [module.policies]
}

# AWX consumer — network-security-secrets — read/list only
module "approle_nwpci_awx_nwsec" {
  source    = "./modules/approle"
  role_name = "nwpci-awx-nwsec"
  policy_names = [
    module.policies.policy_name_self_secret_id,
    module.policies.policy_name_awx_nwsec, # read/list on network-security-secrets
  ]
  token_ttl     = var.approle_token_ttl
  token_max_ttl = var.approle_token_max_ttl
  depends_on    = [module.policies]
}

# SMS owner — network-atm-secrets — full access
module "approle_nwpci_sms_nwauto" {
  source    = "./modules/approle"
  role_name = "nwpci-sms-nwauto"
  policy_names = [
    module.policies.policy_name_self_secret_id,
    module.policies.policy_name_sms_nwauto, # full access on network-atm-secrets
  ]
  token_ttl     = var.approle_token_ttl
  token_max_ttl = var.approle_token_max_ttl
  depends_on    = [module.policies]
}

# SMS owner — network-data-secrets — full access
module "approle_nwpci_sms_nwdata" {
  source    = "./modules/approle"
  role_name = "nwpci-sms-nwdata"
  policy_names = [
    module.policies.policy_name_self_secret_id,
    module.policies.policy_name_sms_nwdata, # full access on network-data-secrets
  ]
  token_ttl     = var.approle_token_ttl
  token_max_ttl = var.approle_token_max_ttl
  depends_on    = [module.policies]
}

# SMS owner — network-lb-secrets — full access
# Note: role is named "nwpci-sms-lb" (not nwpci-sms-nwlb) per specification.
module "approle_nwpci_sms_lb" {
  source    = "./modules/approle"
  role_name = "nwpci-sms-lb"
  policy_names = [
    module.policies.policy_name_self_secret_id,
    module.policies.policy_name_sms_nwlb, # full access on network-lb-secrets
  ]
  token_ttl     = var.approle_token_ttl
  token_max_ttl = var.approle_token_max_ttl
  depends_on    = [module.policies]
}

# SMS owner — network-security-secrets — full access
module "approle_nwpci_sms_nwsec" {
  source    = "./modules/approle"
  role_name = "nwpci-sms-nwsec"
  policy_names = [
    module.policies.policy_name_self_secret_id,
    module.policies.policy_name_sms_nwsec, # full access on network-security-secrets
  ]
  token_ttl     = var.approle_token_ttl
  token_max_ttl = var.approle_token_max_ttl
  depends_on    = [module.policies]
}

###############################################################################
# AppRole credential storage in KV
#
# Bootstrap credentials (role_id + secret_id) are written into KV v2 so that
# the consuming systems (SMS, AWX) can retrieve them from a known, policy-
# governed path rather than receiving them out-of-band from an operator.
#
# All credentials are stored in the network-atm-secrets engine because:
#   - SMS roles have full write access to that engine and can self-manage their
#     own credential entries.
#   - AWX roles have read-only access and can retrieve them securely.
#   - Using a single engine for credential storage avoids cross-engine
#     policy complexity.
#
# Path conventions:
#   SMS credentials → global/vault/<environment>/sms/<role-name>
#     Example: global/vault/dev/sms/nwpci-sms-nwauto
#
#   AWX credentials → global/vault/dev/<environment>/<role-name>
#     Example: global/vault/dev/dev/nwpci-awx-nwauto
#     The literal "dev" prefix is per specification — it indicates these are
#     AWX automation credentials (read: "dev tooling") regardless of target env.
#
# Every credential entry includes custom_metadata:
#   expiry_date         — ISO 8601 date after which credentials should be rotated
#   pwd_rotation_data   — JSON-encoded rotation context (resource type + netbox_id)
#   pwd_rotation_method — "auto" indicates automated rotation is expected
#   approle_name        — role name for human readability in the Vault UI
#   environment         — target environment label
###############################################################################

# SMS credentials for nwpci-sms-nwauto
module "kv_creds_sms_nwauto" {
  source      = "./modules/kv_secret"
  mount_path  = module.kv_engine_atm.mount_path
  secret_path = "global/vault/${var.environment}/sms/${module.approle_nwpci_sms_nwauto.role_name}"
  role_id     = module.approle_nwpci_sms_nwauto.role_id
  secret_id   = module.approle_nwpci_sms_nwauto.secret_id
  custom_metadata = {
    expiry_date         = var.credential_expiry_date
    pwd_rotation_data   = jsonencode({ accessed_resource = { type = "device", netbox_id = 1234 } })
    pwd_rotation_method = "auto"
    approle_name        = module.approle_nwpci_sms_nwauto.role_name
    environment         = var.environment
  }
  depends_on = [module.kv_engine_atm, module.approle_nwpci_sms_nwauto]
}

# SMS credentials for nwpci-sms-nwdata
module "kv_creds_sms_nwdata" {
  source      = "./modules/kv_secret"
  mount_path  = module.kv_engine_atm.mount_path
  secret_path = "global/vault/${var.environment}/sms/${module.approle_nwpci_sms_nwdata.role_name}"
  role_id     = module.approle_nwpci_sms_nwdata.role_id
  secret_id   = module.approle_nwpci_sms_nwdata.secret_id
  custom_metadata = {
    expiry_date         = var.credential_expiry_date
    pwd_rotation_data   = jsonencode({ accessed_resource = { type = "device", netbox_id = 1234 } })
    pwd_rotation_method = "auto"
    approle_name        = module.approle_nwpci_sms_nwdata.role_name
    environment         = var.environment
  }
  depends_on = [module.kv_engine_atm, module.approle_nwpci_sms_nwdata]
}

# SMS credentials for nwpci-sms-lb
module "kv_creds_sms_lb" {
  source      = "./modules/kv_secret"
  mount_path  = module.kv_engine_atm.mount_path
  secret_path = "global/vault/${var.environment}/sms/${module.approle_nwpci_sms_lb.role_name}"
  role_id     = module.approle_nwpci_sms_lb.role_id
  secret_id   = module.approle_nwpci_sms_lb.secret_id
  custom_metadata = {
    expiry_date         = var.credential_expiry_date
    pwd_rotation_data   = jsonencode({ accessed_resource = { type = "device", netbox_id = 1234 } })
    pwd_rotation_method = "auto"
    approle_name        = module.approle_nwpci_sms_lb.role_name
    environment         = var.environment
  }
  depends_on = [module.kv_engine_atm, module.approle_nwpci_sms_lb]
}

# SMS credentials for nwpci-sms-nwsec
module "kv_creds_sms_nwsec" {
  source      = "./modules/kv_secret"
  mount_path  = module.kv_engine_atm.mount_path
  secret_path = "global/vault/${var.environment}/sms/${module.approle_nwpci_sms_nwsec.role_name}"
  role_id     = module.approle_nwpci_sms_nwsec.role_id
  secret_id   = module.approle_nwpci_sms_nwsec.secret_id
  custom_metadata = {
    expiry_date         = var.credential_expiry_date
    pwd_rotation_data   = jsonencode({ accessed_resource = { type = "device", netbox_id = 1234 } })
    pwd_rotation_method = "auto"
    approle_name        = module.approle_nwpci_sms_nwsec.role_name
    environment         = var.environment
  }
  depends_on = [module.kv_engine_atm, module.approle_nwpci_sms_nwsec]
}

# AWX credentials for nwpci-awx-nwauto
module "kv_creds_awx_nwauto" {
  source      = "./modules/kv_secret"
  mount_path  = module.kv_engine_atm.mount_path
  secret_path = "global/vault/dev/${var.environment}/${module.approle_nwpci_awx_nwauto.role_name}"
  role_id     = module.approle_nwpci_awx_nwauto.role_id
  secret_id   = module.approle_nwpci_awx_nwauto.secret_id
  custom_metadata = {
    expiry_date         = var.credential_expiry_date
    pwd_rotation_data   = jsonencode({ accessed_resource = { type = "device", netbox_id = 1234 } })
    pwd_rotation_method = "auto"
    approle_name        = module.approle_nwpci_awx_nwauto.role_name
    environment         = var.environment
  }
  depends_on = [module.kv_engine_atm, module.approle_nwpci_awx_nwauto]
}

# AWX credentials for nwpci-awx-nwdata
module "kv_creds_awx_nwdata" {
  source      = "./modules/kv_secret"
  mount_path  = module.kv_engine_atm.mount_path
  secret_path = "global/vault/dev/${var.environment}/${module.approle_nwpci_awx_nwdata.role_name}"
  role_id     = module.approle_nwpci_awx_nwdata.role_id
  secret_id   = module.approle_nwpci_awx_nwdata.secret_id
  custom_metadata = {
    expiry_date         = var.credential_expiry_date
    pwd_rotation_data   = jsonencode({ accessed_resource = { type = "device", netbox_id = 1234 } })
    pwd_rotation_method = "auto"
    approle_name        = module.approle_nwpci_awx_nwdata.role_name
    environment         = var.environment
  }
  depends_on = [module.kv_engine_atm, module.approle_nwpci_awx_nwdata]
}

# AWX credentials for nwpci-awx-nwlb
module "kv_creds_awx_nwlb" {
  source      = "./modules/kv_secret"
  mount_path  = module.kv_engine_atm.mount_path
  secret_path = "global/vault/dev/${var.environment}/${module.approle_nwpci_awx_nwlb.role_name}"
  role_id     = module.approle_nwpci_awx_nwlb.role_id
  secret_id   = module.approle_nwpci_awx_nwlb.secret_id
  custom_metadata = {
    expiry_date         = var.credential_expiry_date
    pwd_rotation_data   = jsonencode({ accessed_resource = { type = "device", netbox_id = 1234 } })
    pwd_rotation_method = "auto"
    approle_name        = module.approle_nwpci_awx_nwlb.role_name
    environment         = var.environment
  }
  depends_on = [module.kv_engine_atm, module.approle_nwpci_awx_nwlb]
}

# AWX credentials for nwpci-awx-nwsec
module "kv_creds_awx_nwsec" {
  source      = "./modules/kv_secret"
  mount_path  = module.kv_engine_atm.mount_path
  secret_path = "global/vault/dev/${var.environment}/${module.approle_nwpci_awx_nwsec.role_name}"
  role_id     = module.approle_nwpci_awx_nwsec.role_id
  secret_id   = module.approle_nwpci_awx_nwsec.secret_id
  custom_metadata = {
    expiry_date         = var.credential_expiry_date
    pwd_rotation_data   = jsonencode({ accessed_resource = { type = "device", netbox_id = 1234 } })
    pwd_rotation_method = "auto"
    approle_name        = module.approle_nwpci_awx_nwsec.role_name
    environment         = var.environment
  }
  depends_on = [module.kv_engine_atm, module.approle_nwpci_awx_nwsec]
}

###############################################################################
# Sample Secrets
#
# One device credential is written per engine to validate that:
#   1. The engine is mounted and writable.
#   2. Policy access controls work end-to-end.
#   3. Custom metadata is stored and retrievable.
#
# Path convention: sample/<environment>/devices/<device-name>
#   Example: sample/dev/devices/router-01
#
# Secret payload:
#   { "username": "<admin-user>", "password": "<var.sample_secret_password>" }
#
# Custom metadata follows the same schema as credential entries:
#   expiry_date, pwd_rotation_data, pwd_rotation_method, environment
#
# These are NOT real device credentials. Replace username/password with
# real values or remove sample secrets from production environments.
###############################################################################

locals {
  # Map of sample secret definitions, keyed by a unique label.
  # Each entry contains the target engine mount, KV path, username, and
  # a netbox_id used to populate pwd_rotation_data metadata.
  sample_secrets = {
    # ATM engine — represents a managed ATM network router
    "atm-router-01" = {
      mount_path  = module.kv_engine_atm.mount_path
      secret_path = "sample/${var.environment}/devices/router-01"
      username    = "admin"
      netbox_id   = 1001
    }
    # Data engine — represents a managed data-plane switch
    "data-switch-01" = {
      mount_path  = module.kv_engine_data.mount_path
      secret_path = "sample/${var.environment}/devices/switch-01"
      username    = "netops"
      netbox_id   = 2001
    }
    # LB engine — represents a managed F5 load balancer
    "lb-f5-01" = {
      mount_path  = module.kv_engine_lb.mount_path
      secret_path = "sample/${var.environment}/devices/f5-01"
      username    = "lbadmin"
      netbox_id   = 3001
    }
    # Security engine — represents a managed perimeter firewall
    "security-firewall-01" = {
      mount_path  = module.kv_engine_security.mount_path
      secret_path = "sample/${var.environment}/devices/firewall-01"
      username    = "secadmin"
      netbox_id   = 4001
    }
  }
}

resource "vault_kv_secret_v2" "sample_secrets" {
  # for_each iterates over local.sample_secrets, creating one secret per entry.
  # The map key (e.g. "atm-router-01") becomes the Terraform resource address:
  #   vault_kv_secret_v2.sample_secrets["atm-router-01"]
  for_each = local.sample_secrets

  mount               = each.value.mount_path
  name                = each.value.secret_path
  delete_all_versions = false # Preserve all 10 versions on destroy for audit purposes

  # Secret payload — username and password stored as a flat JSON object.
  # Vault KV v2 wraps this in a versioned data envelope internally.
  data_json = jsonencode({
    username = each.value.username
    password = var.sample_secret_password
  })

  # Custom metadata is stored separately from secret data in KV v2.
  # It is NOT versioned — updates to metadata do not create a new secret version.
  # max_versions here applies only to this specific secret path, overriding
  # the engine-level default.
  custom_metadata {
    max_versions = 10
    data = {
      expiry_date         = var.credential_expiry_date
      # pwd_rotation_data must be a string value in custom_metadata.
      # jsonencode produces a JSON string, satisfying the map(string) constraint.
      pwd_rotation_data   = jsonencode({ accessed_resource = { type = "device", netbox_id = each.value.netbox_id } })
      pwd_rotation_method = "auto"
      environment         = var.environment
    }
  }

  # Explicit dependency on all four engines ensures they are mounted before
  # Terraform attempts to write to them. This guards against race conditions
  # during the first apply when all resources are created in parallel.
  depends_on = [
    module.kv_engine_atm,
    module.kv_engine_data,
    module.kv_engine_lb,
    module.kv_engine_security,
  ]
}

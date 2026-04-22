# vault-terraform

Terraform configuration for HashiCorp Vault — Network PCI platform.

Manages four KV v2 secret engines, nine HCL policies, eight AppRole auth roles, AppRole credential storage, and sample device secrets across multiple deployment environments.

---

## Project layout

```
vault-terraform/
├── main.tf                              # Root orchestrator — instantiates all modules
├── auth.tf                              # Enables the AppRole auth backend (once)
├── variables.tf                         # Root input variable definitions
├── outputs.tf                           # Root outputs (role_ids, paths, policy names)
├── terraform.tfvars.example             # Template — copy to terraform.tfvars
├── Makefile                             # Developer workflow shortcuts
├── .gitignore
│
├── modules/
│   ├── kv_engine/                       # Mounts a KV v2 secret engine
│   │   ├── main.tf                      # vault_mount + vault_kv_secret_backend_v2
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── policy/                          # Creates all Vault HCL policies
│   │   ├── main.tf                      # Nine vault_policy resources
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── templates/
│   │       ├── kv_read_list.tftpl       # Read/list policy (AWX consumer)
│   │       └── kv_full_access.tftpl     # Full CRUD policy (SMS owner)
│   │
│   ├── approle/                         # Creates an AppRole + bootstrap secret_id
│   │   ├── main.tf                      # vault_approle_auth_backend_role + secret_id
│   │   ├── auth_backend.tf              # Data source for the approle backend
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── kv_secret/                       # Writes AppRole credentials into KV v2
│       ├── main.tf                      # vault_kv_secret_v2 with custom_metadata
│       ├── variables.tf
│       └── outputs.tf
│
├── environments/
│   └── dev/
│       ├── backend.hcl                  # Remote state config for dev (S3 template)
│       └── terraform.tfvars             # Dev variable values (.gitignored)
│
└── .github/
    └── workflows/
        └── terraform.yml                # GitHub Actions CI/CD pipeline
```

---

## Resources created

### Secret engines (KV v2)

| Mount path                   | Purpose                               |
|------------------------------|---------------------------------------|
| `network-atm-secrets`        | ATM network device credentials + all AppRole credential storage |
| `network-data-secrets`       | Data-plane switch and router credentials |
| `network-lb-secrets`         | Load balancer (F5, NGINX, HAProxy) credentials |
| `network-security-secrets`   | Firewall and security appliance credentials |

All engines are KV v2 with `max_versions = 10`.

### AppRoles

| Role name            | Consumer | Engine              | Access level |
|----------------------|----------|---------------------|--------------|
| `nwpci-awx-nwauto`   | AWX      | network-atm-secrets   | Read / list  |
| `nwpci-awx-nwdata`   | AWX      | network-data-secrets  | Read / list  |
| `nwpci-awx-nwlb`     | AWX      | network-lb-secrets    | Read / list  |
| `nwpci-awx-nwsec`    | AWX      | network-security-secrets | Read / list |
| `nwpci-sms-nwauto`   | SMS      | network-atm-secrets   | Full access  |
| `nwpci-sms-nwdata`   | SMS      | network-data-secrets  | Full access  |
| `nwpci-sms-lb`       | SMS      | network-lb-secrets    | Full access  |
| `nwpci-sms-nwsec`    | SMS      | network-security-secrets | Full access |

Each role is attached two policies: `nwpci-self-secret-id` (self rotation) and a domain-specific read-only or full-access policy.

### Policies

| Policy name                | Attached to            | Grants                            |
|----------------------------|------------------------|-----------------------------------|
| `nwpci-self-secret-id`     | All 8 roles            | Generate new secret_id for any role |
| `nwpci-awx-nwauto-ro`      | nwpci-awx-nwauto       | Read + list on network-atm-secrets |
| `nwpci-sms-nwauto-rw`      | nwpci-sms-nwauto       | Full CRUD on network-atm-secrets   |
| `nwpci-awx-nwdata-ro`      | nwpci-awx-nwdata       | Read + list on network-data-secrets |
| `nwpci-sms-nwdata-rw`      | nwpci-sms-nwdata       | Full CRUD on network-data-secrets  |
| `nwpci-awx-nwlb-ro`        | nwpci-awx-nwlb         | Read + list on network-lb-secrets  |
| `nwpci-sms-nwlb-rw`        | nwpci-sms-lb           | Full CRUD on network-lb-secrets    |
| `nwpci-awx-nwsec-ro`       | nwpci-awx-nwsec        | Read + list on network-security-secrets |
| `nwpci-sms-nwsec-rw`       | nwpci-sms-nwsec        | Full CRUD on network-security-secrets |

### KV credential paths

AppRole bootstrap credentials are stored in `network-atm-secrets`.

**SMS credentials** → `global/vault/<environment>/sms/<role-name>`
```
global/vault/dev/sms/nwpci-sms-nwauto
global/vault/dev/sms/nwpci-sms-nwdata
global/vault/dev/sms/nwpci-sms-lb
global/vault/dev/sms/nwpci-sms-nwsec
```

**AWX credentials** → `global/vault/dev/<environment>/<role-name>`
```
global/vault/dev/dev/nwpci-awx-nwauto
global/vault/dev/dev/nwpci-awx-nwdata
global/vault/dev/dev/nwpci-awx-nwlb
global/vault/dev/dev/nwpci-awx-nwsec
```

**Sample device secrets** (one per engine) → `sample/<environment>/devices/<device>`
```
network-atm-secrets      sample/dev/devices/router-01
network-data-secrets     sample/dev/devices/switch-01
network-lb-secrets       sample/dev/devices/f5-01
network-security-secrets sample/dev/devices/firewall-01
```

### Custom metadata schema

Every secret (credentials and sample devices) carries this metadata:

```json
{
  "expiry_date": "2027-04-01",
  "pwd_rotation_data": "{\"accessed_resource\":{\"type\":\"device\",\"netbox_id\":1234}}",
  "pwd_rotation_method": "auto",
  "approle_name": "nwpci-sms-nwauto",
  "environment": "dev"
}
```

---

## Prerequisites

- Terraform >= 1.7.0
- Vault CLI on `$PATH` (for helper `make` targets)
- A Vault token with permission to mount engines, create policies, and enable auth methods
- `VAULT_ADDR` and `VAULT_TOKEN` exported in the shell

```bash
export VAULT_ADDR=https://vault.example.internal:8200
export VAULT_TOKEN=<bootstrap-token>
```

---

## Local development run

```bash
# 1. Clone
git clone git@github.com:your-org/vault-terraform.git
cd vault-terraform

# 2. Copy and edit variable values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set vault_address, environment, sample_secret_password

# 3. Initialise without a remote backend
terraform init

# 4. Validate and format check
make validate
make fmt-check

# 5. Preview changes
make plan ENV=dev

# 6. Apply
make apply ENV=dev

# 7. View outputs
terraform output
terraform output -json approle_role_ids
```

---

## Environment-specific deployments

```bash
# Initialise with an environment-specific remote state backend
make init ENV=staging

# Plan against staging tfvars
make plan ENV=staging

# Apply the staging plan
make apply ENV=staging
```

---

## Verifying resources after apply

```bash
# List all mounted engines — confirm four network-* mounts exist
vault secrets list -detailed

# List all AppRole roles — confirm eight nwpci-* roles exist
vault list auth/approle/role

# Inspect a specific role's configuration
vault read auth/approle/role/nwpci-awx-nwauto

# List all policies
vault policy list

# Read a policy's HCL
vault policy read nwpci-sms-nwauto-rw

# Read stored AppRole credentials
vault kv get network-atm-secrets/global/vault/dev/sms/nwpci-sms-nwauto

# Read credential metadata only
vault kv metadata get network-atm-secrets/global/vault/dev/sms/nwpci-sms-nwauto

# Read a sample secret
vault kv get network-lb-secrets/sample/dev/devices/f5-01
```

---

## AppRole authentication — curl examples

Replace `<VAULT_ADDR>`, `<role_id>`, and `<secret_id>` with values from `terraform output -json`.

```bash
# Step 1 — retrieve role_id and secret_id from Terraform outputs
ROLE_ID=$(terraform output -json approle_role_ids | jq -r '.nwpci_awx_nwauto')
SECRET_ID=$(terraform output -json approle_secret_ids | jq -r '.nwpci_awx_nwauto')

# Step 2 — authenticate and capture the client token
RESPONSE=$(curl -s \
  --request POST \
  --data "{\"role_id\":\"${ROLE_ID}\",\"secret_id\":\"${SECRET_ID}\"}" \
  ${VAULT_ADDR}/v1/auth/approle/login)

APP_TOKEN=$(echo $RESPONSE | jq -r '.auth.client_token')

# Step 3 — read a secret using the token
curl -s \
  --header "X-Vault-Token: ${APP_TOKEN}" \
  ${VAULT_ADDR}/v1/network-atm-secrets/data/sample/dev/devices/router-01 \
  | jq .data.data

# Step 4 — read custom metadata for a path
curl -s \
  --header "X-Vault-Token: ${APP_TOKEN}" \
  ${VAULT_ADDR}/v1/network-atm-secrets/metadata/sample/dev/devices/router-01 \
  | jq .data.custom_metadata

# Step 5 — self-rotate the secret_id (requires nwpci-self-secret-id policy)
curl -s \
  --header "X-Vault-Token: ${APP_TOKEN}" \
  --request POST \
  --data '{}' \
  ${VAULT_ADDR}/v1/auth/approle/role/nwpci-awx-nwauto/secret-id \
  | jq .data.secret_id
```

---

## CI pipeline

The GitHub Actions workflow at `.github/workflows/terraform.yml` runs:

| Trigger                     | Jobs run                      |
|-----------------------------|-------------------------------|
| Pull request to `main`      | lint → plan (posts PR comment) |
| Push to `main`              | lint → plan → apply (dev)      |
| Manual `workflow_dispatch`  | lint → plan → apply (any env)  |

### Required GitHub Actions secrets

| Secret name                    | Description                                    |
|--------------------------------|------------------------------------------------|
| `VAULT_ADDR`                   | Vault server URL                               |
| `CI_VAULT_ROLE_ID`             | AppRole role_id for the CI service account     |
| `CI_VAULT_SECRET_ID`           | AppRole secret_id for the CI service account   |
| `SAMPLE_SECRET_PASSWORD`       | Injected as `TF_VAR_sample_secret_password`    |
| `AWS_TERRAFORM_STATE_ROLE_ARN` | IAM role ARN for OIDC-based S3 state access    |

---

## Adding a new environment

1. Create `environments/<env>/backend.hcl` with S3 bucket and key for that environment.
2. Create `environments/<env>/terraform.tfvars` with `environment = "<env>"` and other values.
3. Run:
   ```bash
   make init ENV=<env>
   make plan ENV=<env>
   make apply ENV=<env>
   ```

---

## Credential rotation workflow

1. Application authenticates: `POST /v1/auth/approle/login` with `role_id` + `secret_id`.
2. Vault returns a service token valid for `token_ttl` (default 1h).
3. Before the token expires, the application calls:
   `POST /v1/auth/approle/role/<role>/secret-id` (permitted by `nwpci-self-secret-id`).
4. Vault returns a new `secret_id`. Application stores it locally and discards the old one.
5. On next authentication cycle, the new `secret_id` is used.
6. The old bootstrap `secret_id` (generated by Terraform) should be revoked after first rotation:
   ```bash
   vault write auth/approle/role/<role>/secret-id-accessor/destroy \
     secret_id_accessor=<accessor-from-terraform-output>
   ```

---

## Security considerations

- `terraform.tfvars` is `.gitignored`. Never commit credentials to source control.
- All `secret_id` Terraform outputs are marked `sensitive = true`. They are redacted in `plan` and `apply` console output but remain in state. Use encrypted remote state.
- Bootstrap `secret_id` values should be treated as one-time credentials. Rotate immediately after first use.
- In production, set `secret_id_num_uses = 1` in the approle module to enforce single-use per secret_id.
- Set `secret_id_ttl` to a finite window (e.g. `"720h"`) so stale credentials auto-expire.
- Enable `secret_id_bound_cidrs` to restrict credentials to known automation host IP ranges.
- Enable `seal_wrap = true` on KV engines when an HSM or cloud KMS Vault seal is configured.

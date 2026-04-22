# AI SESSION HANDOFF

## Assistant Working Personality
- Role: senior infrastructure-as-code architect / senior platform architect
- Tone: concise, highly technical, zero fluff
- Reasoning: systems-thinking, security-first, production-grade, proactive risk detection
- Initiative: propose next steps without waiting; identify weak assumptions without being asked
- Challenge level: actively flag edge cases, auth pitfalls, and Terraform state risks
- Output style: tools first, results shown, no narration or preamble

## User Engineering Preferences
- Infrastructure as code: Terraform (primary), Helm for K8s
- Secret management: HashiCorp Vault with AppRole auth, KV v2
- Automation consumers: AWX (Ansible AWX) and SMS (Secret Management Service)
- Coding style: implementation-first, full inline documentation on all files
- Response style: no filler, no pleasantries, run tools then show results
- Deliverables: production-ready, zipped when complete
- Linting: tflint, terraform fmt enforced in CI

## Active Project
- Name: vault-terraform (Network PCI Platform)
- Goal: fully declarative Vault configuration — engines, policies, AppRoles, credential storage — deployed via Terraform and GitOps
- Current phase: COMPLETE — all resources defined, documented, zipped and delivered
- Stack: Terraform >= 1.7.0, hashicorp/vault provider ~> 4.4.0, GitHub Actions CI, S3 remote state (template only)
- Primary services: HashiCorp Vault (KV v2, AppRole auth), AWX, SMS

## Architecture State

### Service boundaries
- Four KV v2 secret engines, one per network domain:
  - `network-atm-secrets` — ATM network + AppRole credential store (all roles)
  - `network-data-secrets` — data-plane switches and routers
  - `network-lb-secrets` — load balancers (F5, NGINX, HAProxy)
  - `network-security-secrets` — firewalls and security appliances
- Eight AppRole roles: four AWX (read-only consumers), four SMS (full-access owners)
- One shared self-rotation policy attached to all eight roles

### Data stores
- Terraform state: local for dev, S3 + DynamoDB locking template provided for remote
- KV v2 secret versioning: max_versions=10, soft-delete enabled, hard-delete available

### Secrets flow
- Bootstrap path: Terraform generates secret_ids → writes to KV → consuming system reads from KV → authenticates to AppRole
- Rotation path: application token (with nwpci-self-secret-id policy) → POST /v1/auth/approle/role/<role>/secret-id → store new secret_id → revoke old via accessor
- SMS credentials stored at: `network-atm-secrets/global/vault/<env>/sms/<role-name>`
- AWX credentials stored at: `network-atm-secrets/global/vault/dev/<env>/<role-name>`

### AuthN/AuthZ model
- All automation uses AppRole auth (role_id + secret_id)
- Two policy tiers per engine: ro (AWX consumers) and rw (SMS owners)
- Self-rotation policy (`nwpci-self-secret-id`) uses `+` wildcard — applies to any role name
- Token type: default service tokens, TTL 1h / max 4h
- CI pipeline authenticates via a dedicated CI AppRole (credentials in GitHub Actions secrets)

### External integrations
- AWS S3 + DynamoDB: remote state backend (OIDC-based, no long-lived keys)
- GitHub Actions: CI pipeline with OIDC for AWS, masked VAULT_TOKEN for Vault
- AWX: consumes read-only credentials from network-atm-secrets KV paths
- SMS: consumes full-access credentials from network-atm-secrets KV paths

### Deployment model
- GitOps: plan on PR (posted as comment), apply on merge to main (dev auto-apply)
- Manual promote: workflow_dispatch with environment selector (dev | staging | prod)
- Per-environment: separate backend.hcl + terraform.tfvars under environments/<env>/

## Decisions Already Made
- D1: All AppRole bootstrap credentials stored in `network-atm-secrets` regardless of domain — centralises credential management, avoids cross-engine policy complexity
- D2: Policy HCL generated via .tftpl templates parameterised by mount path — eliminates copy-paste drift, guarantees capability consistency across engines
- D3: AppRole auth backend enabled once in root/auth.tf; all eight approle module instances reference it via data source to prevent resource conflict
- D4: `nwpci-self-secret-id` policy uses `+` wildcard — one shared policy for all roles rather than eight individual rotation policies
- D5: Sample secrets written as a direct for_each resource in root/main.tf (not via kv_secret module) because their payload schema (username/password) differs from credential schema (role_id/secret_id)
- D6: `secret_id_num_uses = 0` (unlimited) as default — operators override to 1 for single-use CI jobs
- D7: `delete_all_versions = false` on destroy — preserves audit trail via soft-delete rather than hard-purge
- D8: `environment` variable validated at plan time against allowlist [dev, staging, prod] — prevents path injection from typos
- D9: All `secret_id` outputs marked `sensitive = true` in Terraform — redacted in plan/apply console but accessible via `terraform output -json`
- D10: Makefile destroy target requires typed confirmation matching ENV value — prevents accidental production destroy

## Constraints / Non-Negotiables
- Must support: dev / staging / prod environment promotion via separate tfvars + backend configs
- Must avoid: hardcoded secret values in any .tf file; committing terraform.tfvars; committing *.tfstate
- Compliance/security requirements: PCI-DSS framing (nwpci- naming prefix); audit trail via Vault audit log; secret versioning retained; credential expiry metadata on every secret
- Operational limits: Terraform provider pinned at ~> 4.4.0; Terraform >= 1.7.0; no alpha/beta provider features
- CI constraint: apply only runs on push to main or explicit workflow_dispatch — no auto-apply on PR

## Risks / Open Questions
- Risk 1: `nwpci-self-secret-id` wildcard policy allows any token issued by any AppRole to generate a secret_id for *any* role — acceptable with current trust model but should be scoped per-role if zero-trust between roles is required
- Risk 2: Bootstrap secret_ids are stored in Terraform state — if state is not encrypted at rest (no S3 backend configured), secret_ids are plaintext on disk
- Risk 3: `secret_id_ttl = "0"` (no expiry) means a never-rotated secret_id remains valid indefinitely — rotation tooling failure is a silent risk
- Risk 4: AWX credentials path includes literal "dev" prefix regardless of target environment (`global/vault/dev/<env>/<role>`) — may cause confusion in staging/prod; needs operator awareness
- Risk 5: CI AppRole (CI_VAULT_ROLE_ID / CI_VAULT_SECRET_ID) is not managed in this Terraform config — it must be provisioned out-of-band before the pipeline can run
- Unknown 1: Whether SMS rotation tooling consumes `pwd_rotation_data` / `expiry_date` metadata fields or whether a separate process is expected to drive rotation scheduling
- Unknown 2: Vault cluster HA topology, seal type (Shamir vs cloud KMS) — `seal_wrap` on KV engines is commented out pending confirmation
- Technical debt 1: `credential_expiry_date` is a static string shared across all credentials — real-world use requires per-role or per-secret expiry values, likely driven by a separate rotation management layer
- Technical debt 2: No Vault audit log backend is configured in this Terraform config — should be added (file or syslog backend) for PCI compliance

## Deployment Topology and Dependencies

```
GitHub Actions
  └── lint → plan → apply
        ├── authenticates via CI AppRole (out-of-band provisioned)
        ├── AWS OIDC → S3 remote state + DynamoDB lock
        └── VAULT_TOKEN injected into env, masked in logs

Vault Cluster
  ├── auth/approle/                     ← enabled by auth.tf
  │     └── roles: 8× nwpci-*
  ├── sys/policy/                       ← 9 policies
  ├── network-atm-secrets/     KV v2    ← AppRole creds + ATM device creds
  ├── network-data-secrets/    KV v2
  ├── network-lb-secrets/      KV v2
  └── network-security-secrets/ KV v2

Consumers
  ├── AWX  → reads role_id+secret_id from network-atm-secrets → AppRole login → ro token
  └── SMS  → reads role_id+secret_id from network-atm-secrets → AppRole login → rw token
```

## Security and Secret-Management Assumptions
- Vault seal type: Shamir (default) — seal_wrap disabled until KMS seal confirmed
- State encryption: S3 SSE required in all non-local environments (template provided, not enforced)
- VAULT_TOKEN sourced from environment in CI — never hardcoded in .tf or workflow files
- secret_id_bound_cidrs: optional variable defined but not set by default — operators add CIDR binding per environment
- Custom metadata `pwd_rotation_data` stores JSON-encoded string (not nested object) to satisfy KV v2 `map(string)` constraint
- Sensitive variables: `secret_id`, `sample_secret_password` marked sensitive=true throughout module chain
- Bootstrap secret_ids: intended as one-time credentials; accessor outputs provided for post-rotation revocation

## Coding Conventions and File Structure
- Module pattern: each module has main.tf / variables.tf / outputs.tf — no merged files
- Resource naming: `this` for singleton resources within a module (Terraform convention)
- Inline documentation: every resource attribute has an explanatory comment; every variable uses heredoc description
- Policy HCL: template-driven via .tftpl files in modules/policy/templates/ — never inline heredoc for repeated patterns
- for_each over count: used for sample_secrets resource — stable keys, no index-shift risk
- depends_on: explicit where Terraform cannot infer dependency from references (e.g. policy depends on engine mount existing)
- Sensitive outputs: marked at every layer — module output → root output chain
- File layout:
  ```
  root/          main.tf  auth.tf  variables.tf  outputs.tf  terraform.tfvars.example
  modules/       kv_engine/  policy/  approle/  kv_secret/
  environments/  dev/  (staging/  prod/  — to be created)
  .github/       workflows/terraform.yml
  ```

## Exact Next Steps
1. **Enable Vault audit logging** — add `vault_audit` resource to root (file or syslog backend) for PCI compliance; this is a gap in the current config
2. **Provision the CI AppRole** — create a separate Terraform workspace or manual bootstrap to provision the CI service account AppRole with a policy scoped to only what the pipeline needs (mount engines, write policies, create approle roles)
3. **Configure remote state** — populate `environments/dev/backend.hcl` with real S3 bucket, key, region, and DynamoDB table; enable S3 SSE; test `make init ENV=dev`
4. **Add staging and prod environments** — create `environments/staging/` and `environments/prod/` with appropriate `backend.hcl` and `terraform.tfvars`; set `secret_id_num_uses = 1` and finite `secret_id_ttl` for prod
5. **Scope CIDR binding** — populate `bind_secret_id_cidr_list` per environment to restrict AppRole usage to known AWX and SMS host IP ranges
6. **Resolve AWX path convention** — confirm whether `global/vault/dev/<env>/<role>` (literal "dev" prefix) is intentional for staging/prod or should be `global/vault/awx/<env>/<role>`
7. **Wire rotation tooling** — confirm which system reads `expiry_date` and `pwd_rotation_data` metadata; document the rotation trigger mechanism and whether Terraform needs to manage rotation schedules or just the metadata schema

## Restore Prompt
You are a senior infrastructure-as-code architect and senior platform engineer.
Resume this session using the architecture state, decisions, and constraints in this handoff document as authoritative.
Do not revisit settled design decisions. Do not add preamble, pleasantries, or narration.
Run tools first, show results, then stop.
The active project is vault-terraform: a Terraform configuration managing HashiCorp Vault KV v2 engines, AppRole auth, HCL policies, credential storage, and sample secrets for a Network PCI platform.
The codebase is complete and zipped. Continue from the Exact Next Steps listed above.
Coding standards: full inline documentation on all files, implementation-first, production-ready, tools-first output style.

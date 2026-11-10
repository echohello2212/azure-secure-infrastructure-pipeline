# Azure Secure Infrastructure Pipeline (ASIP)

A hands-on Azure and Terraform project built around three themes: **secure by design**, **scalability** and **replicability**. Everything is defined as code, so the environment can be deployed, destroyed and rebuilt at any time.

> This is a learning project. It will grow as my skills do, and the scope, direction and this README will change with it.

**Built with:** Azure, Terraform
**Tested with:** Terraform 1.16.5, Azure CLI 2.91.0, AzureRM provider 4.x (exact version in each `.terraform.lock.hcl`)

## Architecture

Five separate Terraform roots, each with its own state file.

| Root | Holds | Lifecycle |
|---|---|---|
| `network/` | Resource group, VNet, subnets, NSGs, Log Analytics workspace, private DNS zones for blob and SQL, Defender plan settings | Long-lived |
| `datastores/` | Storage account and container, SQL server and database, private endpoints for blob and SQL | Long-lived, protected |
| `compute/` | Frontend and backend Linux VMs | Deployed for testing |
| `connectivity/` | Application Gateway with WAF, Azure Bastion, gateway diagnostics | Deployed for testing |
| `frontdoor/` | Azure Front Door and its WAF policy | Validated, not deployed |

```
rg-asip
└── vnet-asip (10.0.0.0/16)
    ├── snet-frontend      (10.0.1.0/24)  nsg-frontend
    ├── snet-backend       (10.0.2.0/24)  nsg-backend
    ├── AzureBastionSubnet                nsg-bastion
    ├── snet-appgw         (10.0.4.0/24)  nsg-appgw
    └── snet-endpoints     (10.0.5.0/24)  nsg-endpoints
```

Resources are named by type with a short prefix and no purpose suffix, because the lab has one of each. With several, names would carry the purpose and environment.

| Subnet | Role | Accepts traffic from |
|---|---|---|
| `snet-appgw` | The only public entry point: gateway and WAF | The internet (admin IP only, during tests) |
| `snet-frontend` | Frontend VMs | Gateway subnet (HTTP), Bastion (SSH) |
| `snet-backend` | Backend VMs, which reach the data tier only through the endpoints subnet | Frontend subnet (443), Bastion (SSH) |
| `AzureBastionSubnet` | Administration, so no VM needs a public IP | The admin IP |
| `snet-endpoints` | Private endpoints for blob and SQL, the single entry to the data tier. No compute | Backend subnet (443 blob, 1433 SQL) |

Each subnet has one role and its own NSG, so traffic is allowed one hop at a time and a compromise in one tier cannot reach the next directly (segmentation, least privilege). The endpoints subnet holds only the private endpoints, so every rule about reaching the data tier is in one place.

**Why separate roots.** Each root has its own lifecycle, so the costly, disposable parts (gateway, Bastion, VMs) can be destroyed after every session while the network and the data stay put. Separate state also limits the blast radius: a bad apply or destroy in one root cannot touch another root's resources. Anything that stores data lives in `datastores/`, out of reach of a routine teardown. The roots find each other through data sources, not remote state lookups. That keeps coupling loose and means a root never needs read access to another root's state, which is least privilege applied to the tooling. Dependencies run one way: `network` → `datastores` → `compute` → `connectivity`.

## Security design

Security is layered (defense in depth), so no single control is the only thing between the internet and the data. Following a request through the environment:

1. **The edge.** The gateway is the only public entry point. Its NSG denies inbound traffic by default, and the WAF (OWASP 3.2) runs in **Prevention** mode, so injection attempts get a `403`. Detection mode was tested first to see what the rules catch before enforcing them: observe, then enforce. For tests, a temporary rule opens the gateway to the admin IP only.
2. **Segmentation.** The frontend accepts HTTP from the gateway subnet only, and the backend accepts 443 from the frontend only. Each hop allows one source and one port, so a compromised tier cannot reach arbitrary tiers (least privilege, lateral movement limited).
3. **Administration.** No VM has a public IP and login is by SSH key only. Admin access goes through Azure Bastion, restricted to the admin IP, so the management plane has a small attack surface and strong authentication.
4. **The data path.** The backend reaches blob storage and SQL through private endpoints in a dedicated subnet. Its NSG accepts 443 (blob) and 1433 (SQL) from the backend subnet only, the backend allows outbound to nothing but those two ports on that subnet, and private DNS zones resolve the service names to the endpoints' private addresses. Both services have public network access off, so there is no route to the data from the internet. This protects **confidentiality** by removing the path, not by guarding it. DNS only answers where the endpoint is, the NSG decides who connects: the frontend resolves the private address too, but its connection times out.
5. **The storage account.** Authentication is Entra-only (shared keys off), so every access is a named identity that is authorized by role, not a shared secret anyone could leak. Anonymous access is off and TLS 1.2 is the minimum. Cross-tenant replication is off because the data might be PII or other sensitive information. Versioning and 7-day soft delete protect **integrity** and **availability** against bad writes and accidental deletion. The storage firewall denies by default and admits only the admin IP, and only while public access is switched on.
6. **The database.** The SQL server is Entra-only, so there is no password to store or rotate, and its public network access is off. Like blob, it is reached only through a private endpoint, on 1433 from the backend subnet. The serverless database pauses after 30 minutes idle, and its backups are local only, which suits a lab.
7. **Posture.** Defender for Cloud's free tier assesses the whole environment. The paid plans for VMs, SQL and storage are pinned to Free in code, so a plan switched on in the portal shows up as a diff on the next `plan`.
8. **Accountability.** Gateway firewall and access logs go to a Log Analytics workspace. That is the audit trail, the accounting part of **AAA**: who reached the gateway, what the WAF matched and what it did about it. The workspace is protected from accidental deletion for that reason.

State lives in Azure Storage with Azure AD auth only, no shared keys, no public blob access, TLS 1.2 minimum, versioning, soft delete and a delete lock.

Sizing was kept proportionate to the lab. Logs are kept 30 days, and a business would export them to archive storage for long-term retention. The daily log cap of 1 GB is a cost guard that shows a limiter in place, not a value tuned to real traffic. In production it would be based on expected traffic and the designated budget.

## Front Door

Written and validated in `frontdoor/`, but not tested. My Azure account type does not allow Front Door, so the gateway is the public edge. The code stays in the repo and can be applied on a paid subscription. Nothing else depends on it.

**Not included:** an origin lock on the gateway (an `X-Azure-FDID` header check). The service tag in the NSG rule covers every customer's Front Door, so the gateway should also reject requests that do not carry this Front Door's ID. Add it before real use. Steps and details are in the [quickstart](docs/quickstart.md#front-door).

## Prerequisites

- Azure subscription (Owner for the state bootstrap, Contributor afterwards)
- Azure CLI, Terraform (>= 1.16.5), Git
- PowerShell or Bash
- An SSH key pair (public key path is passed as a variable)

## Deploy

1. Sign in: `az login`
2. Run `scripts/bootstrap-state.ps1` once. It creates the state storage.
3. Put the storage account name it prints in each root's `backend.tf`.
4. Set host-specific values as environment variables (nothing environment-specific lives in the repo):

   ```powershell
   $env:TF_VAR_subscription_id = (az account show --query id -o tsv)
   $env:TF_VAR_location = "<azure-region>"
   $env:TF_VAR_admin_ip = "<your-public-ip>"
   $env:TF_VAR_ssh_public_key_path = "<path-to-public-key>"
   $env:TF_VAR_sql_admin_login = (az ad signed-in-user show --query userPrincipalName -o tsv)
   ```

5. In order `network/`, `datastores/`, `compute/`, `connectivity/`, run:

   ```
   terraform init
   terraform fmt
   terraform validate
   terraform plan
   terraform apply
   ```

   Read the plan before applying. A second `plan` should report `No changes`. `frontdoor/` is not part of the deploy.

The gateway accepts no public traffic by default. To test it, a temporary rule opens it to the admin IP, see the quickstart.

## Docs

`docs/quickstart.md` is the operations runbook. Its purpose is to let me, or anyone else, resume a session by copying and pasting instead of re-reading the whole project. It will keep growing: any procedure worth repeating gets a section.

Structure, in the order you need it:
- **Best practice and order of operations:** habits, then startup and teardown.
- **Environment and checks:** variables, admin IP, SQL admin login, Azure checks.
- **Verification:** gateway health and test requests, the endpoint and private path checks, changing WAF mode, querying the logs.
- **Ready-to-paste snippets:** temporary NSG rules (with the actual rule to copy), temporary storage access, removing `prevent_destroy` from the five protected resources, and the Front Door steps with the origin-lock note.

## Test results

| Test | Expected | Result |
|---|---|---|
| SSH to frontend and backend through Bastion | Works | Pass |
| Frontend to backend on 443 | Open | Pass |
| Frontend to backend on a port not in the rules | Blocked | Pass |
| Gateway backend health | Healthy | Pass |
| WAF Detection mode, injection attempt | Not blocked | Pass |
| WAF Prevention mode, injection attempt | `403` | Pass |
| WAF Prevention mode, normal request | `200` | Pass |
| Gateway firewall and access logs in the workspace | Rows in both tables | Pass |
| Storage name from the backend VM | Private endpoint address | Pass |
| Storage name from the frontend VM | Private endpoint address (DNS is not access control) | Pass |
| Backend to the storage endpoint | Service answers | Pass |
| Frontend to the storage endpoint | Blocked (timeout) | Pass |
| Private endpoint connections (blob and SQL) | `Approved` | Pass |
| Storage public network access | `Disabled`, firewall `Deny` | Pass |
| Storage over the public path (own computer) | Refused by the service (`403`), public access denied | Pass |
| Blob container | Private, listed through the management plane | Pass |
| Defender plans | `Free`, except the platform-managed baseline | Pass |

Not yet tested: a SQL connection from the backend (the path is built, the test needs a deploy), authenticated access to storage (the backend has no managed identity or role yet), SSH from frontend to backend (should be blocked), backend outbound to the internet after the deny rule.

## Destroy

Destroy in reverse order, then check only the long-lived resources are left:

```
cd connectivity && terraform destroy
cd ../compute && terraform destroy
az resource list --resource-group rg-asip --output table
```

The gateway, Bastion, public IPs and VMs bill while they exist. `network/` and `datastores/` stay deployed. The data resources are protected by `prevent_destroy` on purpose, see below. The state storage is outside these roots and is not touched.

## Design decisions

- **Terraform:** cloud-agnostic and repeatable. The environment is rebuilt from code, not clicked together in the portal.
- **`for_each` over named sets:** VM counts are variables, so scaling is a number change.
- **Bastion Basic:** enough for browser SSH to VMs in one VNet. Standard adds native client, file transfer and peered-network access. Premium adds private-only deployment and session recording.
- **Environment variables:** values that change per host stay out of the repo.
- **Pinned image version:** Ubuntu 24.04 LTS, version fixed for reproducibility.
- **`prevent_destroy` only on stateful resources:** the storage account and its container, the SQL server and its database (data protection), and the log workspace (the audit trail). Disposable resources are rebuilt on purpose. The limit: it guards only Terraform, so a portal deletion bypasses it. Production would add management locks or immutability. The procedure to remove it is in the quickstart.
- **Entra-only storage:** shared keys off was tried first as the hardened setting, with the provider told to use Entra ID for data-plane calls. A second plan after the apply returned `No changes`, which confirmed it works.
- **Entra-only SQL:** password logins are off, so there is no SQL password to store, rotate or leak. The admin is the identity running Terraform, so in a pipeline it will be the pipeline's identity.
- **Serverless SQL, local backups:** the smallest serverless tier with auto-pause, because a lab database sits idle. I could not find the free-limit argument in the provider docs, so it uses the paid tier. Production would use geo-redundant backups.
- **Defender settings are subscription-wide:** they belong in their own governance root. At this scale they sit in `network/`, which is long-lived and applied first, so monitoring exists before the VMs and gateway do.
- **Front Door kept separate:** no working root depends on it, and the NSG rule that lets it in is a copy-paste snippet in `frontdoor/`, not code in `network/`.
- **Uniformity across roots and modules:** the same file names, backend layout and naming everywhere, because variables and settings are what quietly differ between roots. IaC is meant to be replicable, and copying is the fastest way to replicate. The risk is carelessness: copy, paste, assume it is right, and get sloppy. So after copying, know which values must change (state key, names, variables), then run `fmt`, `validate` and `plan` and read the result. This project hit it: a new root with no `backend.tf`, and a copied backend that kept the wrong state key.

## Production options

What I would change with a real budget and real traffic:

- IP allow and block lists at the edge
- Front Door Premium: managed rules, bot protection and Private Link, with the origin lock
- DDoS Protection and Azure Firewall
- Private endpoints and self-hosted runners for the state storage
- Archive export for logs, with the daily cap sized from traffic and budget
- Management locks on stateful resources
- Vaulted backups for blob, and geo-redundant backups for SQL
- An HTTPS listener on the gateway

## Known lab trade-offs

These trade-offs reflect the lab's scale and focus. In an organization, the tiers, services and security measures are chosen by need and by how important each service is: the more critical the data or the service, the stronger the controls, and the lower the risk, the lighter and cheaper they can be. Where relevant, the items below name what production would change.

- The gateway serves HTTP only, on a single instance.
- Frontend outbound traffic is open.
- Every VM in the VNet can resolve the storage account's private address. DNS shows where it is, not who may connect. Separate zones per tier would hide it, at the cost of more moving parts.
- The state storage accepts public network connections. Authentication is still required, shared keys are off, and its name appears in `backend.tf`, which is acceptable for that reason. Production would use private endpoints and self-hosted runners.
- No NAT gateway. VMs cannot reach the internet.
- Bastion has a public IP, limited to the admin IP by NSG. Premium private-only deployment would remove it.
- Logs are kept 30 days with no archive.
- The SQL admin login is kept out of the repo (environment variable) but stored in state, which is protected. With Entra-only auth it grants nothing on its own.
- SQL backups are local only, and blob relies on soft delete and versioning. The VMs are not backed up, because they are rebuilt from code.
- Defender's `Discovery` and `FoundationalCspm` plans show as `Standard`. They are the platform-managed free baseline and cost nothing.

## Lessons learned

- **A passing plan does not mean a passing apply.** `validate` accepted the gateway, but the apply failed with "one of `host` or `pick_host_name_from_backend_http_settings` must be set" on the health probe.
- **Another root's resources need a lookup.** In `datastores/`, `azurerm_subnet.endpoints_subnet.id` fails with "undeclared resource". The correct reference is `data.azurerm_subnet.endpoints_subnet.id`.
- **Provider upgrades rename arguments.** `private_endpoint_network_policies_enabled = true` was rejected on provider 4.0, and the form is now `private_endpoint_network_policies = "Enabled"`.
- **Account limits show up at apply.** A free-trial subscription refused Front Door at apply, although `validate` had passed.
- **The second plan is the real test.** The hardened storage settings (keys off, public access closed) only proved safe when a plan right after the apply said `No changes`.
- **Review the diff before you apply.** `git diff` caught NSG rules pasted into the wrong block, which would have removed the `GatewayManager` rule from the gateway's NSG.
- **Test with a valid request.** A bare request to the storage account returned `400 InvalidQueryParameterValue` from the backend. The service rejected it as malformed, so it said nothing about access. A request with `?comp=list` is valid, so the service has to decide.
- **Unused allow rules are attack surface.** The backend NSG still allowed outbound to `AzureMonitor` and `AzureBackup` although no agent or backup existed. Removing them made the rule list match what the backend actually does.
- **An interrupted apply leaves orphans.** The gateway and Bastion existed in Azure but not in state, and had to be deleted by hand.

## Next steps

- Azure Policy: every subnet has an NSG (the built-in definition only audits)
- Drift management experiments
- GitHub Actions with OIDC: plan on pull requests, deploy and scheduled destroy workflows
- Modules for the VMs and the NSGs, and a `for_each` lookup for the frontend NICs, once the pipeline works

## Status

- [x] Remote state bootstrap
- [x] Network, NSGs and Bastion subnet
- [x] Linux VMs
- [x] Azure Bastion
- [x] Segmentation tests (core)
- [x] Application Gateway with WAF
- [x] Logging (Log Analytics, gateway logs)
- [x] Private endpoints and blob container
- [ ] Front Door (written and validated, not tested)
- [x] Azure SQL
- [ ] Azure Policy: every subnet has an NSG
- [x] Defender for Cloud (free tier)
- [ ] Drift management experiments
- [ ] GitHub Actions with OIDC
- [ ] Modules

## Repository structure

```
.
├── .gitignore
├── README.md
├── docs/
│   └── quickstart.md
├── scripts/
│   └── bootstrap-state.ps1
├── network/
├── datastores/
├── compute/
├── connectivity/
└── frontdoor/
```

Every root holds its own `backend.tf`, `providers.tf`, `variables.tf` and `.terraform.lock.hcl`, plus the files for its resources. A root that reads another root's resources keeps those lookups in `lookups.tf`.
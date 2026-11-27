# Azure Secure Infrastructure Pipeline (ASIP)

A hands-on Azure and Terraform project built around three themes: **secure by design**, **scalability** and **replicability**. Everything is defined as code, so the environment can be deployed, destroyed and rebuilt at any time.

> This is a learning project. It will grow as my skills do, and the scope, direction and this README will change with it.

**Built with:** Azure, Terraform, GitHub Actions
**Tested with:** Terraform 1.16.5, Azure CLI 2.91.0, AzureRM provider 4.x (exact version in each `.terraform.lock.hcl`)

## Architecture

Five separate Terraform roots, each with its own state file.

| Root | Holds | Lifecycle |
|---|---|---|
| `network/` | VNet, subnets, NSGs, Log Analytics workspace, private DNS zones for blob and SQL, Defender plan settings | Long-lived |
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

The resource group `rg-asip` is created by a bootstrap script, not by Terraform, and every root finds it with a data source. The reasoning is in [Access model](#access-model).

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
5. **The storage account.** Authentication is Entra-only (shared keys off), so every access is a named identity that is authorized by role, not a shared secret anyone could leak. Anonymous access is off, TLS 1.2 is the minimum and secure transfer (HTTPS only) is enforced. Cross-tenant replication is off because the data might be PII or other sensitive information. Versioning and 7-day soft delete protect **integrity** and **availability** against bad writes and accidental deletion. The storage firewall denies by default and admits only the admin IP, and only while public access is switched on.
6. **The database.** The SQL server is Entra-only, so there is no password to store or rotate, and its public network access is off. Like blob, it is reached only through a private endpoint, on 1433 from the backend subnet. The administrator is an Entra group. That is a role inside the database engine, separate from Azure RBAC: Contributor on the resource group does not make an identity a database admin, and a database admin gets no Azure permissions from it. Access is granted and revoked by group membership. The serverless database pauses after 30 minutes idle, and its backups are local only, which suits a lab.
7. **Posture.** Defender for Cloud's free tier assesses the whole environment. The paid plans for VMs, SQL and storage are pinned to Free in code, so a plan switched on in the portal shows up as a diff on the next `plan`.
8. **Accountability.** Gateway firewall and access logs go to a Log Analytics workspace. That is the audit trail, the accounting part of **AAA**: who reached the gateway, what the WAF matched and what it did about it. The workspace is protected from accidental deletion for that reason.

State lives in Azure Storage with Azure AD auth only, no shared keys, no public blob access, TLS 1.2 minimum, versioning, soft delete and a delete lock.

**Where values live.** Environment-specific values (subscription, region, admin IP, SSH key, group ID) are kept in as few places as possible: environment variables locally, GitHub secrets in the pipeline, and nothing in the repo. The pipeline holds no credentials at all, because it signs in with OIDC. Commands that return an ID or another sensitive value put it in a variable or on the clipboard, so it never appears in the terminal, in a log or in pasted output. The limit is the state file, which stores the values of the resources it manages, so that cannot be avoided. That is why the state storage is protected as described above.

Sizing was kept proportionate to the lab. Logs are kept 30 days, and a business would export them to archive storage for long-term retention. The daily log cap of 1 GB is a cost guard that shows a limiter in place, not a value tuned to real traffic. In production it would be based on expected traffic and the designated budget.

## Access model

The pipeline runs as two Entra identities (managed identities) that sign in with OIDC. No password, key or secret is stored for them: GitHub proves which repository and which branch or environment is asking, and Azure trusts only that exact match.

| Identity | Used for | Access |
|---|---|---|
| plan | Pull request plans and drift sweeps | Reader on `rg-asip`, Security Reader on the subscription, blob access to the state container |
| deploy | Apply and destroy, only through the `deploy` environment | Contributor on `rg-asip`, Security Admin on the subscription, blob access to the state container |

What I decided, and why:

- **One identity per job.** The plan identity can only read, so a pull request can never change anything. Only the deploy identity can write, and only after approval. That is least privilege and separation of duties in the tooling.
- **Contributor on one resource group, not the subscription.** I started with Contributor on the whole subscription to get the first pipeline running, then narrowed it. A faulty or compromised run can now only affect what is inside `rg-asip`.
- **Security Admin on the subscription, for Defender only.** Defender's plan settings are subscription-scoped, so the deploy identity needs one subscription-level role to apply them. Security Admin is the narrowest role that can, far less than the subscription Contributor I began with and then removed. The plan identity gets the read-only twin, Security Reader, so a pull request can still plan those settings without being able to change them.
- **The resource group and the identities come from scripts, not Terraform.** I run them once, with my own login and Owner rights, because creating role assignments needs more than Contributor. The pipeline cannot give itself access, so a compromised run cannot widen its own permissions.
- **The trade-off.** Contributor on the group can still delete the group itself. For a lab I accept that, with the approval gate as the guard.
- **Approval and separation of duties.** The `deploy` environment needs my approval, has a short wait timer and only runs from `main`. One person cannot be both the initiator and a separate authorizer, and GitHub's prevent-self-review cannot be used in a one-person repo. So these controls guard against mistakes, not against a compromised account. In a team, a second person would approve.

## Pipeline

Every change goes through a pull request, and the pipeline does the Azure work. A run is always plan, then approval, then apply.

| Workflow | Runs on | Does |
|---|---|---|
| `ci` | Pull requests and pushes to `main`, or manually | Validates all five roots, then scans with checkov and actionlint |
| `plan` | Pull requests, or manually | On a PR, plans `network` and `datastores` read-only. On manual dispatch, sweeps all roots and fails on drift (`-detailed-exitcode`) |
| `deploy` | Push to `main` (`network/` or `datastores/`), or manually | Plans, waits for approval, applies |
| `destroy` | Manually | Checks a typed confirmation, plans the destroy, waits for approval, destroys |
| `teardown` | Manually | Checks a typed confirmation, then destroys the whole environment in dependency order |

`deploy` calls one reusable workflow, `deploy-root`, so the steps exist once and the caller only decides which roots run and in what order. `network` and `datastores` are long-lived and deploy on push. `compute` and `connectivity` cost money while they exist, so they are manual only. `full startup` runs everything in dependency order. The pipeline does not deploy `frontdoor/`.

**Plan on the run page.** The plan is copied into the run's summary, next to the approval. The person approving reads exactly what will change without digging through logs. Authorization only means something if the approver sees what they are authorizing.

**One environment, several approvals.** Every root deploys through the same `deploy` environment, so when a run fans out, GitHub's approval prompt shows only the environment name, not which root it is gating. The approver has to open the specific job and read its plan to know what they are confirming; the prompt alone cannot tell two pending approvals apart.

**A failed check reports the environment, not the change.** The plan and drift checks read live infrastructure, so a red run can mean the environment is incomplete — roots not deployed, a dependency missing — rather than the code being wrong. The manual all-roots sweep is the clearest case: against a torn-down environment every root except `network` fails at the data-source lookup, because what it reads is not there yet. Before merging on a red check, confirm why it failed and weigh the change's scope of impact: a failure caused by a missing environment is not the same as a broken change.

**More than one control.**
- Apply and destroy share one concurrency group, so two runs never touch state at once. The state lock is a second layer.
- Destroy needs the root's name typed in as confirmation before anything is planned, and then an approval. A typo stops it at the first job.
- Third-party actions are pinned to commit SHAs, not tags, so a moved tag cannot change what runs. `dependabot` opens a weekly pull request to move those pins forward, so pinning does not mean they go stale.

**Do not cancel a run in the middle of an apply or destroy.** It can leave resources half-changed (drift) and the state locked. Cancelling at the approval prompt is safe, and rejecting is cleaner.

**Full teardown.** A separate `teardown` workflow takes the whole environment down in dependency order, behind a typed confirmation and an approval. It removes every `prevent_destroy = true` automatically for the run, so the guards never have to be edited by hand, and each root's destroy is independent, with a report step that lists what succeeded and what failed instead of stopping at the first error. A fresh sign-in before each root keeps the run from outliving its short-lived token. Front Door is not deployed here, so its destroy step is kept as an inert `.example` to paste in on a paid subscription.

## Security scanning

Two scanners run in `ci`, on every pull request and push to `main`, so a change that weakens the configuration or the workflows is caught before it merges.

- **checkov** scans the Terraform and the GitHub Actions workflows for insecure settings. No framework is set, so it auto-detects both. Every finding is dealt with rather than silenced: most are fixed in code (secure transfer on storage, extension operations off on the VMs, the `id-token` permission scoped on the workflows), and the few that remain carry an inline `#checkov:skip=<id>:<reason>` that says why — a deliberate lab choice, a platform-managed baseline, or a false positive. The scan has to pass with no un-suppressed findings.
- **actionlint** lints the workflow files and runs shellcheck over their `run` blocks. It caught fragmented redirects into `$GITHUB_STEP_SUMMARY` (SC2129), now written as single grouped writes.

Both are pinned by commit SHA or image digest, like every other third-party action. Running them locally and the local-vs-CI version caveat are in the [quickstart](docs/quickstart.md#security-scanning).

## Front Door

Written and validated in `frontdoor/`, but not tested and not part of the pipeline. My Azure account type does not allow Front Door, so the gateway is the public edge. The code stays in the repo and can be applied on a paid subscription. Nothing else depends on it.

**Not included:** an origin lock on the gateway (an `X-Azure-FDID` header check). The service tag in the NSG rule covers every customer's Front Door, so the gateway should also reject requests that do not carry this Front Door's ID. Add it before real use. Steps and details are in the [quickstart](docs/quickstart.md#front-door).

## Prerequisites

- Azure subscription, and Owner (or User Access Administrator) for the two bootstrap scripts. They create role assignments, which Contributor cannot do.
- A GitHub repository with a `deploy` environment and the secrets listed in the [quickstart](docs/quickstart.md#variables-and-secrets)
- An Entra security group, `sg-asip-sql-admins`, with yourself as a member
- Azure CLI, Terraform (>= 1.16.5), Git
- GitHub CLI (`gh`), authenticated, for the identity bootstrap
- PowerShell or Bash
- An SSH key pair (the public key's content is passed as a variable)

## Deploy

1. Sign in: `az login`
2. Run `scripts/bootstrap-state.ps1` once. It creates the state storage.
3. Put the storage account name it prints in each root's `backend.tf`.
4. Run `scripts/bootstrap-pipeline-identity.ps1` once, with `ASIP_GITHUB_REPO` set to `owner/repo` and `gh` authenticated. It creates the identity group, the plan and deploy identities with their OIDC credentials and roles, and `rg-asip`.
5. Add the secrets and the `deploy` environment in GitHub (see the quickstart).
6. Deploy from GitHub: Actions, Deploy, Run workflow, and pick a root. Or run it locally, below.

To run locally, set host-specific values as environment variables (nothing environment-specific lives in the repo):

```powershell
$env:TF_VAR_subscription_id = (az account show --query id -o tsv)
$env:TF_VAR_location = "<azure-region>"
$env:TF_VAR_admin_ip = "<your-public-ip>"
$env:TF_VAR_ssh_public_key = (Get-Content "<path-to-public-key>")
$env:TF_VAR_sql_admin_object_id = (az ad group show --group sg-asip-sql-admins --query id -o tsv)
```

Then, in order `network/`, `datastores/`, `compute/`, `connectivity/`, run:

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
- **Sign in, best practice and order of operations:** habits, then startup and teardown.
- **Variables and secrets:** every value, where it is set locally and in GitHub, and how to get it. Plus the identity bootstrap, running the workflows and what to do when a run is stuck.
- **Security scanning and recovery:** running the scanners locally, and reconciling state after a partial teardown.
- **Checks and verification:** Azure checks, who holds what, gateway health and test requests, the endpoint and private path checks, changing WAF mode, querying the logs.
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

Pipeline:

| Test | Expected | Result |
|---|---|---|
| Pull request plan of `network` and `datastores` | Read-only plan in the run summary | Pass |
| Manual deploy of `network`, `datastores` and `full startup` | Plan, approval, apply | Pass |
| `compute` deployed and destroyed through the workflows | Works | Pass |
| Destroy with a wrong confirmation | Stops at the first job | Pass |
| Destroy plan rejected at the approval | Nothing destroyed | Pass |
| Approved destroy with nothing to destroy (`frontdoor`) | No changes | Pass |
| Run cancelled while waiting for approval | Nothing changed | Pass |
| Full teardown, rebuild from empty, then plan every root | Destroy clean, rebuild clean, `No changes` | Pass |
| Drift sweep against the deployed environment | All roots `No changes` | Pass |
| checkov and actionlint in `ci` | No un-suppressed findings, workflows lint clean | Pass |

Not yet tested: a SQL connection from the backend (the path is built, the test needs a deploy), authenticated access to storage (the backend has no managed identity or role yet), SSH from frontend to backend (should be blocked), backend outbound to the internet after the deny rule.

## Destroy

From GitHub: Actions, Destroy, Run workflow. Pick `connectivity`, `compute` or `frontdoor`, and type the same name as confirmation. The destroy plan appears on the run page, and nothing is deleted until it is approved. Run `connectivity` first, then `compute`. The long-lived roots are not offered here, on purpose. To take down everything, including the long-lived roots, use the `teardown` workflow instead.

Locally, destroy in reverse order, then check only the long-lived resources are left:

```
cd connectivity && terraform destroy
cd ../compute && terraform destroy
az resource list --resource-group rg-asip --output table
```

The gateway, Bastion, public IPs and VMs bill while they exist. `network/` and `datastores/` stay deployed. The data resources are protected by `prevent_destroy` on purpose, see below. The state storage is outside these roots and is not touched. A teardown that stops part-way needs reconciling before the next deploy, see the [quickstart](docs/quickstart.md#partial-teardown-recovery).

## Design decisions

- **Terraform:** cloud-agnostic and repeatable. The environment is rebuilt from code, not clicked together in the portal.
- **`for_each` over named sets:** VM counts are variables, so scaling is a number change.
- **Bastion Basic:** enough for browser SSH to VMs in one VNet. Standard adds native client, file transfer and peered-network access. Premium adds private-only deployment and session recording.
- **Environment variables:** values that change per host stay out of the repo.
- **SSH key as content:** the public key is passed as the key's content in a variable, not as a file path, because the pipeline's runner has no key file. In GitHub it is a secret.
- **Pinned image version:** Ubuntu 24.04 LTS, version fixed for reproducibility.
- **`prevent_destroy` only on stateful resources:** the storage account and its container, the SQL server and its database (data protection), and the log workspace (the audit trail). Disposable resources are rebuilt on purpose. The limit: it guards only Terraform, so a portal deletion bypasses it. Production would add management locks or immutability. The procedure to remove it is in the quickstart.
- **Entra-only storage:** shared keys off was tried first as the hardened setting, with the provider told to use Entra ID for data-plane calls. A second plan after the apply returned `No changes`, which confirmed it works.
- **Entra-only SQL:** password logins are off, so there is no SQL password to store, rotate or leak. The admin is the Entra group `sg-asip-sql-admins`, not whoever runs Terraform, see the lessons below.
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
- A second reviewer on the deploy environment
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
- The SQL admin group's object ID is kept out of the repo (environment variable or secret) but stored in state, which is protected. It identifies a group and grants nothing on its own.
- A change to `datastores/` alone still goes through the `network` approval first, because `datastores` depends on it.
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
- **Do not take an identity from whoever runs Terraform.** The SQL server is Entra-only, so there is no SQL password and the admin has to be an Entra identity. I first took it from `azurerm_client_config`, which returns whoever is running Terraform. Locally that was me. In the pipeline it is the deploy identity, and on pull requests the plan identity. Two problems followed. Every run from a different identity wanted a different admin, so a second plan never said `No changes`. Worse, an apply from the pipeline would have made a service principal the only admin of the database, with no password login to fall back on, and I would have been locked out. The fix is a stable Entra group as the admin, with its object ID passed in as a variable. Who may administer the database is now decided by group membership.
- **A waiting approval is not idle.** `deploy` and `destroy` share one concurrency group, so a run waiting at an approval gate holds the group and blocks the other workflow until it is approved or rejected.
- **A skipped dependency skips the job.** A job that `needs` another job is skipped when that job is skipped. For the optional chain of roots, the condition is `!failure() && !cancelled()` plus the trigger conditions: run unless something failed or the run was cancelled.
- **An environment secret overrides a repo secret of the same name.** Both identities use `AZURE_CLIENT_ID`. The repo secret is the plan identity, and the `deploy` environment's secret is the deploy identity, so the job's environment picks the identity.
- **Moving a resource out of Terraform needs a `removed` block.** The resource group moved to a bootstrap script. Deleting its resource block would have made the next plan destroy the group and everything in it. A `removed` block with `destroy = false` tells Terraform to forget the group without deleting it. Apply once, check the plan shows nothing destroyed, then delete the block.
- **A manual step you run once is a hole in a rebuild.** The first bootstrap script read the plan identity's existing credential and derived the others from it, so it quietly depended on an identity I had created by hand. A rebuild from scratch would have stopped at the first line. Making the script create the identity itself closed the hole. The way to find these: ask what a fresh clone on a new machine has that you never created in code.
- **An OIDC trust can't always be rebuilt from `owner/repo`.** The pipeline signs in with federated credentials whose *subject* must exactly match what GitHub's token carries. GitHub uses **immutable subject claims**: the subject embeds the numeric owner and repo IDs (`repo:owner@<id>/repo@<id>:...`), not the names, so a deleted-and-recreated repo cannot inherit the old trust — the same reason this project assigns Azure roles by object ID, not display name. A version of the bootstrap built the subject as the plain `repo:owner/repo:...` and overwrote the working credential, breaking every pipeline login with `AADSTS700213`. The fix is to ask GitHub for the real subject prefix (`gh api .../oidc/customization/sub`) and build from it, so nothing is hardcoded and the script stays reproducible.
- **The scanner that gates the merge is the one in CI.** checkov in the pipeline ran a newer version than my local copy and flagged settings my local run had passed, such as enforced HTTPS on storage. A clean scan on my laptop proves nothing on its own; the fixes and the documented skips are written against the version that actually blocks the merge.
- **A scanner reads the code, not the live resource.** checkov reported the gateway as having no WAF, because the WAF is attached through a policy (`firewall_policy_id`) that its inline-block rule cannot see. The control is there; the check just looks in the wrong place. A skip is only honest once the control is confirmed another way, so the reason says exactly that.
- **A checkov skip has to sit inside the block.** The scanner only honours `#checkov:skip` inside the resource it applies to, which is the one place this project keeps a comment in the middle of a block.
- **A long job can outlive its own login.** The teardown signs in with OIDC, and the GitHub token behind that sign-in is valid for only a few minutes. A single job that destroys every root in sequence ran past that window, and the first Entra-only data-plane call after it expired failed with `AADSTS700024`. The fix is a fresh sign-in before each root, so no step runs on a dead token; the sharper fix is one job per root. This is the auth token expiring, a different clock from the job timeout.
- **Continue past a failure and it can destroy what the next root needs.** The teardown let `network` run after `datastores` failed, and `network` deleted the private DNS zones `datastores` still depended on — turning a recoverable failure into a deadlock, because `datastores` could then no longer evaluate its own destroy. A root that depends on another should not run when that other has failed.
- **Anything created or destroyed outside Terraform drifts, and Terraform won't fix it for you.** A resource made or deleted by hand is not in state, so `apply` and `destroy` both ignore it. It then blocks the next `apply` with "already exists," or lingers after a `destroy`. Reconcile it — import it, or delete it via the CLI — before the next deploy. The private DNS zones recreated by hand to break a lookup deadlock became exactly this, and blocked `network apply` until they were deleted again.
- **`prevent_destroy` guards a resource against Terraform, including a local destroy.** The teardown workflow strips these automatically for its run; a destroy run by hand hits them and stops, so the flag has to be flipped off in code first. That is the guard working, not a fault.

## Next steps

- Azure Policy: every subnet has an NSG (the built-in definition only audits)
- Drift management experiments
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
- [x] GitHub Actions with OIDC: plan, deploy and destroy
- [x] Full teardown workflow
- [x] Security scanning in CI (checkov, actionlint) and Dependabot
- [ ] Drift management experiments
- [ ] Modules

## Repository structure

```
.
├── .github/
│   ├── dependabot.yml
│   └── workflows/
├── .gitignore
├── README.md
├── docs/
│   └── quickstart.md
├── scripts/
│   ├── bootstrap-state.ps1
│   └── bootstrap-pipeline-identity.ps1
├── network/
├── datastores/
├── compute/
├── connectivity/
└── frontdoor/
```

Every root holds its own `backend.tf`, `providers.tf`, `variables.tf` and `.terraform.lock.hcl`, plus the files for its resources. A root that reads another root's resources keeps those lookups in `lookups.tf`.
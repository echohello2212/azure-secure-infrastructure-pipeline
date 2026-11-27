# Quickstart

Built for ease: copy, paste and resume. Everything is in order, so you can pick up a session without re-reading the whole project. Setup, architecture and reasoning are in the [README](../README.md).

## Contents

- [Sign in](#sign-in)
- [Best practice](#best-practice)
- [Order of operations](#order-of-operations)
- [Variables and secrets](#variables-and-secrets)
- [Bootstrap the identities](#bootstrap-the-identities)
- [Running the workflows](#running-the-workflows)
- [Security scanning](#security-scanning)
- [Who holds what](#who-holds-what)
- [When a run is stuck](#when-a-run-is-stuck)
- [Partial teardown recovery](#partial-teardown-recovery)
- [Azure checks](#azure-checks)
- [Verify the gateway](#verify-the-gateway)
- [Verify the endpoints](#verify-the-endpoints)
- [Verify the private path](#verify-the-private-path)
- [Changing WAF mode](#changing-waf-mode)
- [Temporary NSG rules](#temporary-nsg-rules)
- [Temporary storage access](#temporary-storage-access)
- [Removing prevent_destroy](#removing-prevent_destroy)
- [Querying the logs](#querying-the-logs)
- [Front Door](#front-door)

## Sign in

```
az login
```

Then check the right subscription is active, see [Azure checks](#azure-checks). With several subscriptions, select one with `az account set --subscription "<subscription-name-or-id>"`. For MFA or tenant errors, see the sign-in fixes under Azure checks.

Only the [bootstrap scripts](#bootstrap-the-identities) need Owner. Everything else works with the access the pipeline identities have.

## Best practice

- **Read every plan before applying.** A passing plan is not a passing apply.
- **Check the folder and the diff.** The prompt must show the root you mean, and `git diff` shows what you are about to change. A result from the wrong folder says nothing.
- **After copying a root or a block, change what must change.** State key, names, variables. Then `fmt`, `validate` and `plan`, and read the result.
- **One change per commit.** Stage by path and check `git diff --cached --stat`.
- **Redact before pasting.** No subscription IDs, IPs or resource IDs in commits, issues or shared output.
- **Keep state out of the repo.** State and saved plans can contain secrets.
- **A second `plan` should say `No changes`.** Anything else is drift or a bug.
- **Costly resources bill while they exist.** The gateway, Bastion and VMs cost money every hour they are left running, so destroy them the same day.
- **Don't create or delete resources by hand.** Anything made or removed outside Terraform drifts: it is not in state, so `apply` and `destroy` ignore it, and it blocks the next `apply` with "already exists." If you must, import it or clean it up before the next deploy, see [Partial teardown recovery](#partial-teardown-recovery).

## Order of operations

**Startup**

1. [Sign in](#sign-in) and set the [variables](#variables-and-secrets) if you work locally.
2. Run the [Azure checks](#azure-checks).
3. `network/`, then `datastores/`. If they are still deployed, `plan` should say `No changes`, and you can move on.
4. `compute/`.
5. `connectivity/`. It looks up the frontend NIC, so `compute/` must be up first. The gateway takes 10-20 minutes.
6. [Verify the gateway](#verify-the-gateway).
7. [Verify the endpoints](#verify-the-endpoints).
8. [Verify the private path](#verify-the-private-path).
9. Add any [temporary rules](#temporary-nsg-rules) last.

Do steps 3-5 from GitHub with the [Deploy workflow](#running-the-workflows) (`full startup` runs them in order), or locally with `init`, `fmt`, `validate`, `plan`, `apply` in each root.

`frontdoor/` is not part of the order. It is validated only, see [Front Door](#front-door).

**Teardown of the disposable roots**

1. Clear the temporary rules and `apply` in `network/`. If you switched on [temporary storage access](#temporary-storage-access), switch it off and `apply` in `datastores/`.
2. `connectivity/` destroy first (the gateway takes 10-20 minutes).
3. `compute/` destroy.
4. Verify only the long-lived resources are left:

```
az resource list --resource-group rg-asip --output table
```

Do steps 2-3 with the [Destroy workflow](#running-the-workflows), or locally with `terraform destroy` in each root.

`network/` and `datastores/` stay deployed. The VNet, subnets, NSGs, DNS zones, workspace, storage account, SQL server and database, endpoints and Defender settings cost little (the serverless database pauses when idle), and the ones that hold data are protected on purpose.

**Full teardown**

To take the whole environment down, including the long-lived roots, use the `teardown` workflow (Actions, Teardown). It destroys every root in dependency order, strips `prevent_destroy` for the run, and re-signs in before each root so the run never outlives its token. If it stops part-way, do not just re-run it, see [Partial teardown recovery](#partial-teardown-recovery).

## Variables and secrets

Nothing environment-specific is stored in the repo. Locally the values are environment variables, set per session. In the pipeline they are GitHub secrets. Commands that return an ID or another sensitive value put it in a variable or on the clipboard, never on screen, and this page follows the same habit.

| Terraform variable | Local variable | GitHub secret | Where the value comes from |
|---|---|---|---|
| `subscription_id` | `TF_VAR_subscription_id` | `AZURE_SUBSCRIPTION_ID` | `az account show --query id -o tsv` |
| `location` | `TF_VAR_location` | `ASIP_LOCATION` | The Azure region you deploy to |
| `admin_ip` | `TF_VAR_admin_ip` | `ASIP_ADMIN_IP` | Your public IP, see [Admin IP](#admin-ip) |
| `ssh_public_key` | `TF_VAR_ssh_public_key` | `ASIP_SSH_PUBLIC_KEY` | The content of the `.pub` file, the key without its comment |
| `sql_admin_object_id` | `TF_VAR_sql_admin_object_id` | `ASIP_SQL_ADMIN_OBJECT_ID` | The group's object ID, see [SQL admin group](#sql-admin-group) |
| | | `AZURE_TENANT_ID` | Your Entra tenant ID |
| | | `AZURE_CLIENT_ID` | See below |

`AZURE_CLIENT_ID` exists twice. The repo secret is the plan identity's client ID. The secret in the `deploy` environment is the deploy identity's, and it overrides the repo secret for jobs that use that environment. Both are copied to the clipboard and pasted into GitHub, never printed.

`ASIP_SSH_PUBLIC_KEY` has to be a **repo-level** secret, not only an environment one, so the read-only `plan` identity can plan `compute/` on the all-roots drift sweep (it runs with no environment).

`sql_admin_login` has a default (the group's name), so it needs no value.

`ASIP_GITHUB_REPO` is a local-only input for the bootstrap script, set to `owner/repo`. It is not a Terraform variable or a GitHub secret. The script uses it to ask GitHub for the repo's OIDC subject prefix, so nothing hardcodes an ID.

**PowerShell**

```powershell
$env:TF_VAR_subscription_id = (az account show --query id -o tsv)
$env:TF_VAR_location = "<azure-region>"
$env:TF_VAR_admin_ip = (curl.exe -s https://api.ipify.org)
$env:TF_VAR_ssh_public_key = (Get-Content "<path-to-public-key>")
$env:TF_VAR_sql_admin_object_id = (az ad group show --group sg-asip-sql-admins --query id -o tsv)
```

**Bash**

```bash
export TF_VAR_subscription_id=$(az account show --query id -o tsv)
export TF_VAR_location="<azure-region>"
export TF_VAR_admin_ip=$(curl -s https://api.ipify.org)
export TF_VAR_ssh_public_key=$(cat "<path-to-public-key>")
export TF_VAR_sql_admin_object_id=$(az ad group show --group sg-asip-sql-admins --query id -o tsv)
```

### Admin IP

`TF_VAR_admin_ip` is the public IP that Bastion, the temporary gateway rule and the storage firewall accept.

- Find yours with any "what is my IP" site, or `curl.exe -s https://api.ipify.org` (use `curl.exe` in PowerShell, `curl` is an alias).
- **It might change** (router restart, new network, VPN). If Bastion or the gateway stops answering, update the variable and re-apply `network/` (and `datastores/` if storage access is on). Update the `ASIP_ADMIN_IP` secret too, or the pipeline keeps the old value.
- Never commit the real value.

### SQL admin group

The SQL server's admin is the Entra group `sg-asip-sql-admins`, so access follows membership and does not depend on who runs Terraform. Its object ID is not committed.

Copy it to the clipboard to paste into the `ASIP_SQL_ADMIN_OBJECT_ID` secret:

```powershell
az ad group show --group sg-asip-sql-admins --query id -o tsv | Set-Clipboard
```

Add a member by object ID:

```powershell
az ad group member add --group sg-asip-sql-admins --member-id "<member-object-id>"
```

## Bootstrap the identities

Run once per subscription, as a user with **Owner** or User Access Administrator. The scripts create role assignments, which Contributor cannot do, and the pipeline cannot do it for itself, by design.

1. `scripts/bootstrap-state.ps1` creates the state storage and its lock.
2. `scripts/bootstrap-pipeline-identity.ps1` creates the identity group, the plan and deploy identities with their OIDC credentials, their roles, and `rg-asip`.

Before the second script, set `ASIP_GITHUB_REPO` to `owner/repo` and sign in to the GitHub CLI (`gh auth login`). The script asks GitHub for the repo's OIDC subject prefix, so it works whether or not the subject uses immutable IDs, with nothing hardcoded. If a pipeline login later fails with `AADSTS700213`, the credential subject no longer matches what GitHub sends — re-run this script to rewrite it.

Run each as a file, from a terminal where `TF_VAR_location`, `TF_VAR_subscription_id` and `ASIP_GITHUB_REPO` are set. The script can be run again safely. Client IDs go to the clipboard and nothing sensitive is printed. Paste the plan identity's into the repo secret `AZURE_CLIENT_ID`, and the deploy identity's into the `deploy` environment's `AZURE_CLIENT_ID`.

Run it before the first `network` deploy, since `network/` looks `rg-asip` up and does not create it.

## Running the workflows

**Deploy:** Actions, Deploy, Run workflow, then pick a root.

| Option | Runs |
|---|---|
| `network` | `network/` |
| `datastores` | `datastores/` (needs `network/`) |
| `compute` | `compute/` (needs `network/`) |
| `connectivity` | `connectivity/` (needs `network/` and `compute/`) |
| `full startup` | All four, in dependency order |

A push to `main` that changes `network/` or `datastores/` also runs automatically. `compute` and `connectivity` never run on a push, because they cost money while they exist.

Each root plans first. Read the plan on the run page, then approve in the `deploy` environment. Nothing is applied before that. Pull requests get a read-only plan and a validate run automatically.

**Plan:** runs automatically on pull requests (a read-only plan of the long-lived roots). Run it manually (Actions, Plan, Run workflow) to sweep every root and surface drift — it fails the job when a root has drifted (`-detailed-exitcode`). The sweep reads live infrastructure, so it only means something against a deployed environment, see the note at the end of this section.

**Destroy:** Actions, Destroy, Run workflow. Pick `connectivity`, `compute` or `frontdoor`, and type the same name as confirmation. A mismatch stops at the first job. Read the destroy plan on the run page, then approve. Run `connectivity` before `compute`. The long-lived roots are not offered, destroy those with the `teardown` workflow or locally after [removing prevent_destroy](#removing-prevent_destroy).

**Teardown:** Actions, Teardown, Run workflow. Pick the scope and type `destroy <scope>` to confirm. It destroys the whole environment in dependency order, strips `prevent_destroy` for the run, and re-signs in before each root. Each root's destroy is independent and reported, so one failure does not hide the others. A part-way failure needs reconciling, see [Partial teardown recovery](#partial-teardown-recovery).

**A red check is not automatically a bad change.** The plan and drift checks read live infrastructure, so a failure can mean the environment is incomplete — roots not deployed, a dependency missing — rather than the code being wrong. Against a torn-down environment every root except `network` fails at the data-source lookup, because what it reads is not there yet. Before merging on red, find out *why* it failed and weigh the change's scope of impact: a missing-environment failure is not the same as a broken change.

## Security scanning

checkov and actionlint run in `ci` on every pull request. Run them locally before pushing:

```
checkov -d . --quiet
actionlint
```

- checkov auto-detects the Terraform and the workflows; no `--framework` needed.
- actionlint reads `.github/workflows/` and runs shellcheck on `run` blocks.

**Local and CI versions drift.** CI may run a newer checkov than your machine and flag settings your local run passed. The CI result is the gate — fix or document against it, not against a clean local pass. `pip install -U checkov` narrows the gap, but treat CI as the source of truth.

To document a finding instead of fixing it, put the skip **inside** the resource block (checkov only honours it there):

```
  #checkov:skip=CKV_AZURE_XXX:reason it is acceptable here
```

## Who holds what

What each identity should hold. Check it when a run fails with `AuthorizationFailed`, or after changing access.

| Identity | Role | Scope |
|---|---|---|
| plan | Reader | `rg-asip` |
| plan | Security Reader | Subscription |
| plan | Storage Blob Data Contributor | State container |
| deploy | Contributor | `rg-asip` |
| deploy | Security Admin | Subscription |
| deploy | Storage Blob Data Contributor | State container |

Security Admin on the subscription lets the deploy identity apply the subscription-scoped Defender plan settings; the plan identity gets the read-only Security Reader for the same reason. A missing Security Admin shows up as a `403` on `Microsoft.Security/pricings` during a `network` apply or destroy.

To check, in your own terminal (nothing goes into a workflow or a log). Load the values into variables and never print them:

```powershell
$principal = az identity show --name id-asip-deploy --resource-group rg-asip-identity --query principalId -o tsv
az role assignment list --assignee $principal --all --query "[].roleDefinitionName" -o tsv
```

Use `id-asip-plan` for the plan identity. This lists role names only, so a role at the wrong scope does not show. To see who holds what on the group:

```powershell
$scope = az group show --name rg-asip --query id -o tsv
az role assignment list --scope $scope --query "[].{role:roleDefinitionName, type:principalType}" -o table
```

The variables only exist in that terminal session.

## When a run is stuck

- **Waiting for approval.** A run at the approval prompt holds the concurrency group, so every other deploy or destroy queues behind it. Approve or reject it. Rejecting is cleaner than cancelling.
- **Do not cancel during an apply or destroy.** It can leave resources half-changed and the state locked.
- **State locked after a cancelled or failed run.** Make sure no run is still active, then in the root's folder: `terraform force-unlock <lock-id>`. The lock ID is in the error message. Then run `plan` and read it before doing anything else.
- **A teardown fails part-way with `AADSTS700024` (assertion not within its valid time range).** The OIDC sign-in token is short-lived, and a single job that destroys every root in sequence can outlive it. This is the auth token, not the job timeout. The workflow re-signs in before each root to avoid it; if it still trips, finish the teardown locally (your own `az login` refreshes normally), then see [Partial teardown recovery](#partial-teardown-recovery).
- **A subnet delete fails with `InUseSubnetCannotBeDeleted`.** Something still occupies the subnet, usually a private endpoint from `datastores/` that was not destroyed. Destroy `datastores/` before `network/`. See [Partial teardown recovery](#partial-teardown-recovery).

## Partial teardown recovery

A teardown can stop half-way: a cancelled run, an expired token, a dependency that blocked a delete. The environment is then part up, part down, and state no longer matches Azure. Do not just re-run it — reconcile first.

1. List what is actually in Azure:

```
az resource list --resource-group rg-asip --output table
```

2. Compare it to each root's state (`terraform -chdir=<root> state list`), then per mismatch:
   - **In Azure but not in state** (an orphan — often a private endpoint left in a subnet, or a resource an interrupted apply created): either `terraform -chdir=<root> import <address> <id>` to bring it under Terraform, or delete it via the CLI.
   - **In state but not in Azure:** `terraform -chdir=<root> state rm <address>`.
3. Once state matches reality, `terraform -chdir=<root> destroy` the root for a clean teardown.

Order still matters: destroy `datastores/` before `network/`, or the private endpoints hold the endpoints subnet open and the subnet delete fails with `InUseSubnetCannotBeDeleted`.

**Anything created or deleted by hand drifts.** It is outside state, so `apply` and `destroy` ignore it. Remove it manually (or import it) **before the next deploy**, or the next `apply` fails with "already exists." The private DNS zones are the usual culprit: recreate them to break a data-source lookup deadlock, and they must be deleted again before the rebuild.

**A guarded resource stops a local destroy.** The `teardown` workflow strips `prevent_destroy` automatically; a local `terraform destroy` does not, so set the flag to `false` in code first, see [Removing prevent_destroy](#removing-prevent_destroy).

## Azure checks

```
az account show --query "{name:name, state:state}" -o table
az vm list-skus --location <azure-region> --size <vm-size> --output table
az security pricing list --query "value[].{name:name, tier:pricingTier}" -o table
```

- Confirm the right subscription is active.
- Confirm `TF_VAR_admin_ip` matches your current public IP.
- VM size availability differs per subscription. Look for `NotAvailableForSubscription` before applying.
- Every Defender plan should show `Free`, except `Discovery` and `FoundationalCspm`. Those two are the platform-managed baseline and cost nothing.
- **If a command fails with an MFA error,** sign in again with `az login --tenant <tenant-id>`. If Terraform still complains about the state storage, add `--scope https://storage.azure.com/.default`. Use `--use-device-code` if no browser opens.

## Verify the gateway

Backend health (wait for `Healthy`):

```
az network application-gateway show-backend-health --name appgw-asip --resource-group rg-asip --query "backendAddressPools[].backendHttpSettingsCollection[].servers[].health" -o tsv
```

Gateway address:

```
az network public-ip show --name pip-appgw --resource-group rg-asip --query ipAddress -o tsv
```

The gateway accepts no public traffic by default. Add the [temporary rule](#temporary-nsg-rules) first, then test (use `curl.exe` in PowerShell, `curl` is an alias):

```
curl.exe -i http://<gateway-ip>/
curl.exe -i "http://<gateway-ip>/?id=1' OR '1'='1"
```

A normal request returns `200`. In Prevention mode the second returns `403`.

## Verify the endpoints

Each private endpoint's connection should be approved:

```
az network private-endpoint show --name pe-blob --resource-group rg-asip --query "privateLinkServiceConnections[].privateLinkServiceConnectionState.status" -o tsv
az network private-endpoint show --name pe-sql --resource-group rg-asip --query "privateLinkServiceConnections[].privateLinkServiceConnectionState.status" -o tsv
```

Expected: `Approved` for both. Anything else means the endpoint is not usable.

The storage account's public path should be closed:

```
az storage account show --name <storage-account> --resource-group rg-asip --query "{public:publicNetworkAccess, default:networkRuleSet.defaultAction}" -o json
```

Expected: `Disabled` and `Deny`.

The container exists and is private. This lists it through the management plane, so it works with the public path closed:

```
az storage container-rm list --storage-account <storage-account> --resource-group rg-asip --output table
```

Expected: the container, with `PublicAccess` of `None`.

## Verify the private path

Checks that only the backend can reach the storage account, and that it does so privately. Connect to each VM through Bastion. Select the **private** key file, not the `.pub`, or Bastion rejects it.

On both VMs, DNS first:

```
nslookup <storage-account>.blob.core.windows.net
```

Both should return an address in the endpoints subnet (`10.0.5.0/24`), because the private DNS zone is linked to the whole VNet. DNS is not access control, so the frontend resolves it too.

Then the connection, on each VM:

```
curl -sS -m 10 "https://<storage-account>.blob.core.windows.net/?comp=list"
```

| VM | Expected | Meaning |
|---|---|---|
| `backend-1` | An XML error body with an authentication or authorization code | The network path works and the service refuses the unauthenticated request |
| `frontend-1` | Timeout, `curl: (28)` | `nsg-endpoints` drops the packet, the service never answers |

- **Use a valid request.** A bare account URL returns `400 InvalidQueryParameterValue` (empty `comp`) from anywhere, so it says nothing about access.
- **Read the `<Code>` in the body.** It shows which check rejected the request. Keep request IDs out of anything committed.
- **To get a `200`,** the VM needs a managed identity with a data role on the account. This is not set up.

## Changing WAF mode

The mode is set in the gateway's WAF policy (`connectivity/waf.tf`).

- **Detection** logs matches and lets the request through. It is invisible without the [diagnostic logs](#querying-the-logs).
- **Prevention** blocks matches with `403`.

After applying a change, **wait 3-5 minutes** before testing. The new mode is not instant.

## Temporary NSG rules

For testing access only, such as admin IP to the gateway on port 80. Only `nsg_appgw` has a marker.

1. Copy the entire rule below.
2. Paste it at the bottom of the `nsg_appgw` block in `network/nsg.tf`, beneath the `#TEMPORARY RULES` tag, before the `#TEMPORARY RULES END` marker.
3. `plan`, check, `apply`.
4. After the session, delete everything beneath the tag and `apply` again.

```terraform
  security_rule {
    name                       = "Allow-Admin-HTTP-In"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = var.admin_ip
    destination_address_prefix = "*"
  }
```

- Use priority 1000 and up. Permanent rules use 100-4000 in steps of 10.
- Don't use a separate `azurerm_network_security_rule` resource. The inline rules overwrite it.
- **Another NSG:** add the same marker and a rule at 1000 or higher, and remove both afterwards.

## Temporary storage access

The storage account has no public access by default. To reach it from your computer:

1. Set the switch for the session:

```powershell
$env:TF_VAR_storage_public_access = "true"
```

2. `plan`, check, `apply` in `datastores/`. Only the admin IP is allowed through the storage firewall.
3. Shared keys are off, so data access needs a role on your own identity (for example Storage Blob Data Contributor).
4. When done, set it back and apply again:

```powershell
$env:TF_VAR_storage_public_access = "false"
```

## Removing prevent_destroy

Five resources hold data or the audit trail and are protected on purpose:

| Resource | File |
|---|---|
| Log Analytics workspace | `network/logging.tf` |
| Storage account | `datastores/storage.tf` |
| Blob container | `datastores/storage.tf` |
| SQL server | `datastores/sql.tf` |
| SQL database | `datastores/sql.tf` |

The `teardown` workflow strips these automatically for its run, so this is only needed for a **local** destroy. To destroy one by hand: set `prevent_destroy = false` in its `lifecycle` block, then run the destroy. Put it back to `true` after a rebuild. A parent takes its children with it, so remove the flag on both the storage account and its container, or on both the SQL server and its database.

`prevent_destroy` only guards Terraform, including a local `terraform destroy`. Deleting in the portal bypasses it.

## Querying the logs

The diagnostic setting sends gateway logs to dedicated tables in the workspace. Open the workspace in the portal, then Logs:

```
AGWFirewallLogs
| take 20
```

```
AGWAccessLogs
| take 20
```

Logs can take a few minutes to appear after a request.

## Front Door

`frontdoor/` is written and validated, but not tested or deployed. To try it on a paid subscription:

1. Deploy `connectivity/`.
2. Paste the rule from `frontdoor/nsg_rule.tf.example` into `nsg_appgw` in `network/nsg.tf` and `apply`.
3. `apply` in `frontdoor/`.

**Not included:** an `X-Azure-FDID` header check. The service tag in the NSG rule covers every customer's Front Door, so the gateway should also block requests whose `X-Azure-FDID` header does not match your own Front Door profile's ID. That is a custom rule on the gateway's WAF policy. The ID only exists after deployment, so check the profile's exported attribute name in the provider documentation.
# Quickstart

Built for ease: copy, paste and resume. Everything is in order, so you can pick up a session without re-reading the whole project. Setup, architecture and reasoning are in the [README](../README.md).

## Contents

- [Best practice](#best-practice)
- [Order of operations](#order-of-operations)
- [Environment variables](#environment-variables)
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

## Best practice

- **Read every plan before applying.** A passing plan is not a passing apply.
- **Check the folder and the diff.** The prompt must show the root you mean, and `git diff` shows what you are about to change. A result from the wrong folder says nothing.
- **After copying a root or a block, change what must change.** State key, names, variables. Then `fmt`, `validate` and `plan`, and read the result.
- **One change per commit.** Stage by path and check `git diff --cached --stat`.
- **Redact before pasting.** No subscription IDs, IPs or resource IDs in commits, issues or shared output.
- **Keep state out of the repo.** State and saved plans can contain secrets.
- **A second `plan` should say `No changes`.** Anything else is drift or a bug.
- **Costly resources bill while they exist.** The gateway, Bastion and VMs cost money every hour they are left running, so destroy them the same day.

## Order of operations

**Startup**

1. Sign in and set the [environment variables](#environment-variables).
2. Run the [Azure checks](#azure-checks).
3. `network/`, then `datastores/`. In each: `init`, `fmt`, `validate`, `plan`, `apply`. If they are still deployed, `plan` should say `No changes`, and you can move on.
4. `compute/`, same steps.
5. `connectivity/`, same steps. It looks up the frontend NIC, so `compute/` must be up first. The gateway takes 10-20 minutes.
6. [Verify the gateway](#verify-the-gateway).
7. [Verify the endpoints](#verify-the-endpoints).
8. [Verify the private path](#verify-the-private-path).
9. Add any [temporary rules](#temporary-nsg-rules) last.

`frontdoor/` is not part of the order. It is validated only, see [Front Door](#front-door).

**Teardown**

1. Clear the temporary rules and `apply` in `network/`. If you switched on [temporary storage access](#temporary-storage-access), switch it off and `apply` in `datastores/`.
2. `connectivity/` destroy first (the gateway takes 10-20 minutes).
3. `compute/` destroy.
4. Verify only the long-lived resources are left:

```
az resource list --resource-group rg-asip --output table
```

`network/` and `datastores/` stay deployed. The VNet, subnets, NSGs, DNS zones, workspace, storage account, SQL server and database, endpoints and Defender settings cost little (the serverless database pauses when idle), and the ones that hold data are protected on purpose.

## Environment variables

Nothing environment-specific is stored in the repo. Set these per session.

**PowerShell**

```powershell
$env:TF_VAR_subscription_id = (az account show --query id -o tsv)
$env:TF_VAR_location = "<azure-region>"
$env:TF_VAR_admin_ip = "<your-public-ip>"
$env:TF_VAR_ssh_public_key_path = "<path-to-public-key>"
$env:TF_VAR_sql_admin_login = (az ad signed-in-user show --query userPrincipalName -o tsv)
```

**Bash**

```bash
export TF_VAR_subscription_id=$(az account show --query id -o tsv)
export TF_VAR_location="<azure-region>"
export TF_VAR_admin_ip="<your-public-ip>"
export TF_VAR_ssh_public_key_path="<path-to-public-key>"
export TF_VAR_sql_admin_login=$(az ad signed-in-user show --query userPrincipalName -o tsv)
```

### Admin IP

`TF_VAR_admin_ip` is the public IP that Bastion, the temporary gateway rule and the storage firewall accept.

- Find yours with any "what is my IP" site, or `curl https://api.ipify.org`.
- **It might change** (router restart, new network, VPN). If Bastion or the gateway stops answering, update the variable and re-apply `network/` (and `datastores/` if storage access is on).
- Never commit the real value.

### SQL admin login

`TF_VAR_sql_admin_login` is the Entra login of the SQL admin. It is personal, so it is read from your sign-in at runtime and never committed. Terraform still stores it in state, which is protected.

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

To destroy one: set `prevent_destroy = false` in its `lifecycle` block, then run the destroy. Put it back to `true` after a rebuild. A parent takes its children with it, so remove the flag on both the storage account and its container, or on both the SQL server and its database.

`prevent_destroy` only guards Terraform. Deleting in the portal bypasses it.

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
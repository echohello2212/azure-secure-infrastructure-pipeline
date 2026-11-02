# Quickstart
 
Built for ease: copy, paste and resume. Everything is in order, so you can pick up a session without re-reading the whole project. Setup and architecture are in the [README](../README.md).
 
## Contents
 
- [Best practice](#best-practice)
- [Order of operations](#order-of-operations)
- [Environment variables](#environment-variables)
- [Azure checks](#azure-checks)
- [Temporary NSG rules](#temporary-nsg-rules)
## Best practice
 
- **Read every plan before applying.** A passing plan is not a passing apply.
- **One change per commit.** Stage by path and check `git diff --cached --stat`.
- **Redact before pasting.** No subscription IDs, IPs or resource IDs in commits, issues or shared output.
- **Keep state out of the repo.** State and saved plans can contain secrets.
- **A second `plan` should say `No changes`.** Anything else is drift or a bug.
- **Costly resources bill while they exist.** The gateway and Bastion cost money every hour they are left running, so destroy them the same day.
## Order of operations
 
**Startup**
 
1. Sign in and set the [environment variables](#environment-variables).
2. Run the [Azure checks](#azure-checks).
3. `network/`, then `compute/`, then `connectivity/`. In each: `init`, `fmt`, `validate`, `plan`, `apply`. If `network/` is still deployed, `plan` should say `No changes`, and you can move on.
4. `connectivity/` looks up the frontend NIC, so `compute/` must be up first.
5. Add any [temporary rules](#temporary-nsg-rules) last.
**Teardown**
 
1. Clear the temporary rules and `apply` in `network/`.
2. `connectivity/` destroy first (the gateway takes 10-20 minutes).
3. `compute/` destroy.
4. Verify nothing is left:
```
az resource list --resource-group rg-asip --output table
```
 
Only network resources should remain. `network/` can stay deployed. The VNet, subnets and NSGs don't bill, so there's no reason to destroy it between sessions.
 
## Environment variables
 
Nothing environment-specific is stored in the repo. Set these per session.
 
**PowerShell**
```powershell
$env:TF_VAR_subscription_id = (az account show --query id -o tsv)
$env:TF_VAR_location = "<azure-region>"
$env:TF_VAR_admin_ip = "<your-public-ip>"
$env:TF_VAR_ssh_public_key_path = "<path-to-public-key>"
```
 
**Bash**
```bash
export TF_VAR_subscription_id=$(az account show --query id -o tsv)
export TF_VAR_location="<azure-region>"
export TF_VAR_admin_ip="<your-public-ip>"
export TF_VAR_ssh_public_key_path="<path-to-public-key>"
```
 
### Admin IP
 
`TF_VAR_admin_ip` is the public IP that Bastion (and the temporary gateway rule) accepts.
 
- Find yours with any "what is my IP" site, or `curl https://api.ipify.org`.
- **It might change** (router restart, new network, VPN). If Bastion or the gateway stops answering, update the variable and re-apply `network/`.
- The IP is used in `nsg-bastion` and the temporary rule, so both pick up the new value on `apply`.
- Never commit the real value.
## Azure checks
 
```
az account show --query "{name:name, state:state}" -o table
az vm list-skus --location <azure-region> --size <vm-size> --output table
```
 
- Confirm the right subscription is active.
- Confirm `TF_VAR_admin_ip` matches your current public IP.
- VM size availability differs per subscription. Look for `NotAvailableForSubscription` before applying.
## Temporary NSG rules
 
For testing access only, such as admin IP to the gateway on port 80.
 
1. Copy the entire rule below.
2. Paste it at the bottom of the `nsg_appgw` block in `network/nsg.tf`, beneath the `#TEMPORARY RULES` tag, before the resource's closing brace.
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
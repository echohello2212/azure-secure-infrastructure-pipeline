# Azure Secure Infrastructure Pipeline (ASIP)

A hands-on Azure and Terraform project built around three themes: **secure by design**, **scalability** and **replicability**. Everything is defined as code, so the environment can be deployed, destroyed and rebuilt at any time.

> This is a learning project. It will grow as my skills do, and the scope, direction and this README will change with it.

**Built with:** Azure, Terraform
**Tested with:** Terraform 1.16.5, Azure CLI 2.91.0, AzureRM provider 4.x (exact version in each `.terraform.lock.hcl`)

## Architecture

Three separate Terraform stacks, each with its own state file, so the costly parts can be destroyed without touching the core network.

| Stack | Holds | Lifecycle |
|---|---|---|
| `network/` | Resource group, VNet, subnets, NSGs | Long-lived |
| `compute/` | Frontend and backend Linux VMs | Deployed for testing |
| `connectivity/` | Azure Bastion and its public IP | Deployed for testing |

```
rg-asip
└── vnet-asip (10.0.0.0/16)
    ├── snet-frontend      (10.0.1.0/24)  nsg-frontend
    ├── snet-backend       (10.0.2.0/24)  nsg-backend
    ├── AzureBastionSubnet                nsg-bastion
    └── snet-appgw         (10.0.4.0/24)  nsg-appgw  (planned use)
```

`compute/` and `connectivity/` look up the network with data sources, so no IDs are hard-coded.

## Security controls

- **Deny-by-default NSGs** on every subnet. Rules are explicit and documented below.
- **No public IPs on VMs.** Admin access goes through Azure Bastion only.
- **SSH key login only**, no passwords. The key stays outside the repo.
- **Segmentation:** the backend accepts 443 from the frontend subnet only. SSH is allowed from the Bastion subnet only.
- **Bastion HTTPS limited to the admin IP**, supplied at deploy time.
- **State in Azure Storage:** Azure AD auth only, no shared keys, no public blob access, TLS 1.2 minimum, versioning, soft delete and a delete lock.

| NSG | Inbound allowed | Everything else |
|---|---|---|
| frontend | 443 from App Gateway subnet, SSH from Bastion subnet | Denied |
| backend | 443 from frontend subnet, SSH from Bastion subnet | Denied |
| bastion | Rules Azure Bastion requires, HTTPS from admin IP | Denied |

The backend also denies outbound by default and allows only Azure Monitor, Storage and Backup on 443.

## Prerequisites

- Azure subscription (Owner for the state bootstrap, Contributor afterwards)
- Azure CLI, Terraform (>= 1.16.5), Git
- PowerShell or Bash
- An SSH key pair (public key path is passed as a variable)

## Deploy

1. Sign in: `az login`
2. Run `scripts/bootstrap-state.ps1` once. It creates the state storage.
3. Put the storage account name it prints in each stack's `backend.tf`.
4. Set host-specific values as environment variables (nothing environment-specific lives in the repo):

   ```powershell
   $env:TF_VAR_subscription_id = (az account show --query id -o tsv)
   $env:TF_VAR_location = "<azure-region>"
   $env:TF_VAR_admin_ip = "<your-public-ip>"
   $env:TF_VAR_ssh_public_key_path = "<path-to-public-key>"
   ```

5. In order `network/`, `compute/`, `connectivity/`, run:

   ```
   terraform init
   terraform fmt
   terraform validate
   terraform plan
   terraform apply
   ```

   Read the plan before applying. A second `plan` should report `No changes`.

## Test results

| Test | Expected | Result |
|---|---|---|
| SSH to frontend and backend through Bastion | Works | Pass |
| Frontend to backend on 443 | Open | Pass |
| Frontend to backend on a port not in the rules | Blocked | Pass |

Not yet tested: SSH from frontend to backend (should be blocked), backend DNS and outbound after the deny rule.

## Destroy

Destroy in reverse order, then check nothing is left:

```
cd connectivity && terraform destroy
cd ../compute && terraform destroy
az resource list --resource-group rg-asip --output table
```

Bastion, public IPs and VMs bill while they exist. The state storage is outside these stacks and is not touched.

## Design decisions

- **Terraform:** cloud-agnostic and repeatable. The environment is rebuilt from code, not clicked together in the portal.
- **Separate stacks and state keys:** each stack has its own lifecycle. Costly parts can be destroyed on demand.
- **Data sources instead of remote state lookups:** looser coupling, and a stack needs no access to another stack's state.
- **`for_each` over named sets:** VM counts are variables, so scaling is a number change.
- **Bastion Basic:** enough for browser SSH to VMs in one VNet. Standard adds native client, file transfer and peered-network access. Premium adds private-only deployment and session recording.
- **Environment variables:** values that change per host stay out of the repo.
- **Pinned image version:** Ubuntu 24.04 LTS, version fixed for reproducibility.
- **`prevent_destroy` only on stateful resources.** Disposable resources are rebuilt on purpose.

## Known lab trade-offs

- Frontend outbound traffic is open.
- The state storage accepts public network connections (authentication still required). Production would use private endpoints and self-hosted runners.
- No NAT gateway. VMs cannot reach the internet.
- Bastion has a public IP, limited to the admin IP by NSG. Premium private-only deployment would remove it.

## Lessons learned

- **A passing plan does not mean a passing apply.** Plan checks the code, not Azure's own rules. Naming, overlaps and SKU capacity only fail at apply.
- **VM SKU availability differs per subscription and region.** Check `az vm list-skus` before choosing a size.
- **Provider defaults can differ from Azure's.** An unset argument showed up as drift on every fresh deploy until I set it explicitly.
- **Reference resources, do not retype names.** Plain-text names hide dependencies from Terraform.
- **Renames of stateful resources need `moved` blocks.** For disposable ones, a plain rename can cause ordering errors.

## Status

- [x] Remote state bootstrap
- [x] Network, NSGs and Bastion subnet
- [x] Linux VMs
- [x] Azure Bastion
- [x] Segmentation tests (core)
- [ ] App Gateway and Front Door
- [ ] Monitoring and logging (Log Analytics, flow logs)
- [ ] Private endpoint for storage
- [ ] Drift management experiments
- [ ] GitHub Actions with OIDC
- [ ] Azure Policy: every subnet has an NSG

## Repository structure

```
.
├── .gitignore
├── README.md
├── scripts/
│   └── bootstrap-state.ps1
├── network/
├── compute/
└── connectivity/
```

Each stack holds `main.tf`, `providers.tf`, `variables.tf`, `backend.tf` and `.terraform.lock.hcl`.
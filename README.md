# Azure Secure Infrastructure Pipeline (ASIP)

A hands-on Azure and Terraform project built around three themes: **secure by design**, **scalability** and **replicability**. Everything is defined as code, so the environment can be deployed, destroyed and rebuilt at any time.

> This is a learning project. It will grow as my skills do, and the scope, direction and this README will change with it.

**Built with:** Azure, Terraform
**Tested with:** Terraform 1.16.5, Azure CLI 2.91.0, AzureRM provider 4.x (exact version in `.terraform.lock.hcl`)

**Planned security controls:** deny-by-default NSGs, no public IPs on VMs, admin access through Azure Bastion, monitoring and logging
**Planned automation:** GitHub Actions

## Architecture

```
rg-asip
└── vnet-asip (10.0.0.0/16)
    ├── snet-frontend   (10.0.1.0/24)
    ├── snet-backend    (10.0.2.0/24)
    └── snet-management (10.0.3.0/24)  -> planned: AzureBastionSubnet
```

## Prerequisites

- Azure subscription (Contributor for the network, Owner for the state bootstrap)
- Azure CLI, Terraform (>= 1.16.5), Git
- PowerShell or Bash

## Deploy

1. Sign in: `az login`
2. Set the host-specific values as environment variables (not stored in the repo):

   ```powershell
   $env:TF_VAR_subscription_id = (az account show --query id -o tsv)
   $env:TF_VAR_location = "<azure-region>"
   ```

   Bash: use `export TF_VAR_...=...` instead. List regions with `az account list-locations -o table`.

3. Deploy (read the plan before applying):

   ```
   terraform init
   terraform fmt
   terraform validate
   terraform plan
   terraform apply
   ```

## Verify

`terraform state list` should show:

```
azurerm_resource_group.rg_asip
azurerm_subnet.backend_subnet
azurerm_subnet.frontend_subnet
azurerm_subnet.management_subnet
azurerm_virtual_network.vnet_asip
```

`terraform plan` should report `No changes`. To check Azure itself:

```powershell
az network vnet subnet list --resource-group rg-asip --vnet-name vnet-asip --query "[].{Name:name, AddressPrefix:addressPrefix}" --output table
```

## Destroy

`terraform destroy` removes everything in the current state (resource group, VNet, subnets) after you confirm with `yes`. Resources outside this state, such as the state storage, are not touched.

## Design decisions

- **Terraform:** cloud-agnostic, scalable and efficient. The environment is rebuilt from code, not clicked together in the portal.
- **Frontend and backend subnets:** closer to a real production environment than a flat network, and I want experience with that. It also gives NSGs clear boundaries to enforce later.
- **Management subnet:** will be renamed `AzureBastionSubnet` (Bastion requires that exact name, minimum /26).
- **Environment variables:** values that change from device to device (subscription, region) come from the host, not from `variables.tf`. This keeps the repo reusable and free of environment-specific data.
- **Separate state for cost-heavy components (planned):** services such as a NAT gateway or application gateway bill while they exist. In their own state they can be deployed and destroyed on demand without touching the core network.
- **Version constraints:** Terraform `>= 1.16.5`, AzureRM `~> 4.0`. The lock file is committed so everyone gets the same provider versions.

## Remote state (in progress)

Terraform state is moving to an Azure storage account, so it does not depend on one machine and a pipeline can use it.

**Why a bootstrap script?** Terraform cannot use a backend that does not exist yet, so `scripts/bootstrap-state.ps1` creates it with the Azure CLI. It is the one part not created by Terraform. Run it once.

The state lives in its own resource group (`rg-asip-tfstate`) so destroying the workload cannot delete it. Secure by design:

- No public blob access, no shared keys, TLS 1.2 minimum
- Versioning and 7-day soft delete for recovery
- `CanNotDelete` lock on the resource group
- Access through a role scoped to the container only
- LRS redundancy: enough for a lab, cheaper and simpler than zone or geo redundancy

**Planned migration:** back up local state, add a `backend "azurerm"` block, run `terraform init -migrate-state`, then verify with `terraform state list` and `terraform plan`.

## Security notes

- `.gitignore` excludes state, variable files, saved plans, crash logs and `.terraform/`. State can contain secrets. The lock file is committed on purpose.
- No credentials in the code.
- **Known lab trade-off:** the state storage accepts public network connections, because GitHub-hosted runners use changing IPs. Authentication is still required (Azure AD only). Production would use private endpoints and self-hosted runners.

## Lessons learned

- **Resource references create dependencies.** Plain-text names caused a `ResourceGroupNotFound` error because Terraform saw no link between resources.
- **Provider names come from the resource prefix.** `azure_` instead of `azurerm_` sent Terraform looking for a provider that does not exist. `terraform providers` exposed it.
- **Placeholders must be replaced.** One was passed as a region and rejected by the provider.
- **Git history can be rewritten before a push.** I fixed a commit with an interactive rebase after taking a backup branch.

## Status

- [x] Provider and variable configuration
- [x] Resource group, VNet and three subnets deployed
- [x] Git repository with clean history
- [x] State bootstrap script written
- [ ] Bootstrap run and state migrated
- [ ] Network security groups
- [ ] VM and Azure Bastion
- [ ] Monitoring and logging
- [ ] Drift management experiments
- [ ] GitHub Actions pipeline

## Repository structure

```
.
├── .gitignore
├── .terraform.lock.hcl
├── README.md
├── main.tf
├── providers.tf
├── variables.tf
└── scripts/
    └── bootstrap-state.ps1
```
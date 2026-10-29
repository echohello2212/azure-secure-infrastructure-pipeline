#Bootstrap Terraform State
#Run once. Needs az login, TF_VAR_location set and Owner rights on the subscription

#Stop if a PowerShell command fails (az commands are checked below)
$ErrorActionPreference = "Stop"

#Startup banner
Write-Host ""
Write-Host "ASIP Terraform State Bootstrap" -ForegroundColor Cyan
Write-Host ""

#Location comes from the Terraform environment variable
$location = $env:TF_VAR_location
if (-not $location) {
    Write-Host "Error: TF_VAR_location is not set. Please set the Azure region before running this script." -ForegroundColor Red
    exit 1
}

#Resource names
$stateResourceGroup = "rg-asip-tfstate"
$randomNumber = Get-Random -Minimum 10000 -Maximum 99999
$storageAccount = "asiptfstate$randomNumber"   #lowercase letters and numbers only, has to be globally unique
$containerName = "tfstate"
$lockName = "lock-asip-tfstate"

#Azure login verification
$subscriptionId = az account show --query id --output tsv
if (-not $subscriptionId) {
    Write-Host "Error: Not logged in to Azure CLI. Please login and set the subscription." -ForegroundColor Red
    exit 1
}
$subscriptionName = az account show --query name --output tsv

#Display subscription name and location
Write-Host "Subscription: $subscriptionName" -ForegroundColor Gray
Write-Host "Location: $location" -ForegroundColor Gray
Write-Host ""
Read-Host "Right subscription? Press Enter to continue, Ctrl+C to stop"

#1. Resource group
Write-Host "Creating resource group..." -ForegroundColor Cyan
az group create `
    --name $stateResourceGroup `
    --location $location `
    --output none
#Exit code: stop if the previous az command failed
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Resource group could not be created." -ForegroundColor Red
    exit 1
}
Write-Host "Resource group ready" -ForegroundColor Green

#2. Storage account
#Standard (HDD) Locally Redundant Storage, general-purpose v2 account
#HTTPS only, no public blob access, no shared key access (Azure AD only)
#TLS 1.2 minimum. As of Oct 2026 Azure Storage can't enforce TLS 1.3 as the minimum
Write-Host "Creating storage account..." -ForegroundColor Cyan
az storage account create `
    --name $storageAccount `
    --resource-group $stateResourceGroup `
    --location $location `
    --sku Standard_LRS `
    --kind StorageV2 `
    --https-only true `
    --min-tls-version TLS1_2 `
    --allow-blob-public-access false `
    --allow-shared-key-access false `
    --output none
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Storage account could not be created." -ForegroundColor Red
    exit 1
}
Write-Host "Storage account ready" -ForegroundColor Green

#3. Versioning and soft delete (7 days)
Write-Host "Enabling versioning and soft delete..." -ForegroundColor Cyan
az storage account blob-service-properties update `
    --account-name $storageAccount `
    --resource-group $stateResourceGroup `
    --enable-versioning true `
    --enable-delete-retention true `
    --delete-retention-days 7 `
    --enable-container-delete-retention true `
    --container-delete-retention-days 7 `
    --output none
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Versioning and soft delete could not be enabled." -ForegroundColor Red
    exit 1
}
Write-Host "Versioning and soft delete enabled" -ForegroundColor Green

#4. Blob container (created through Resource Manager so no data role is needed yet)
Write-Host "Creating tfstate container..." -ForegroundColor Cyan
az storage container-rm create `
    --storage-account $storageAccount `
    --resource-group $stateResourceGroup `
    --name $containerName `
    --output none
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Container could not be created." -ForegroundColor Red
    exit 1
}
Write-Host "Container ready" -ForegroundColor Green

#5. Role assignment (Blob Data Contributor on the container only)
Write-Host "Assigning role..." -ForegroundColor Cyan
#Object ID of the signed-in user, who receives the role
$userId = az ad signed-in-user show --query id --output tsv
if (-not $userId) {
    Write-Host "Error: Signed-in user could not be found. Please copy your user object ID from the portal." -ForegroundColor Red
    exit 1
}
#Full resource ID of the storage account
$accountId = az storage account show --name $storageAccount --resource-group $stateResourceGroup --query id --output tsv
#Scope = the tfstate container only (least privilege)
$scope = "$accountId/blobServices/default/containers/$containerName"
#Owner and Contributor manage resources (control plane), so Blob Data Contributor is also needed for the data plane
#Scope adds data plane access on top of the control plane roles, limited to the tfstate container
az role assignment create `
    --assignee-object-id $userId `
    --assignee-principal-type User `
    --role "Storage Blob Data Contributor" `
    --scope $scope `
    --output none
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Role could not be assigned." -ForegroundColor Red
    exit 1
}
Write-Host "Role assigned" -ForegroundColor Green

#6. Wait for the role to take effect
#If terraform init later fails with an authorization error, wait a few minutes and try again
Write-Host "Waiting 2 minutes for the role to take effect..." -ForegroundColor Yellow
Start-Sleep -Seconds 120

#7. Resource lock (last step)
#Remove later with: az lock delete --name lock-asip-tfstate --resource-group rg-asip-tfstate
Write-Host "Creating resource lock..." -ForegroundColor Cyan
az lock create `
    --name $lockName `
    --resource-group $stateResourceGroup `
    --lock-type CanNotDelete `
    --output none
Write-Host "Resource lock created" -ForegroundColor Green

#Values for the Terraform backend block
Write-Host ""
Write-Host "Done. Values for the backend block:" -ForegroundColor Green
Write-Host "resource_group_name  = `"$stateResourceGroup`"" -ForegroundColor Gray
Write-Host "storage_account_name = `"$storageAccount`"" -ForegroundColor Gray
Write-Host "container_name       = `"$containerName`"" -ForegroundColor Gray
Write-Host "key                  = `"network.tfstate`"" -ForegroundColor Gray
Write-Host "use_azuread_auth     = true" -ForegroundColor Gray
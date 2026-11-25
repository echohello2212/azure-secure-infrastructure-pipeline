#Bootstrap pipeline identities
#Creates the identity group, the plan, deploy and teardown identities with their credentials and roles, and rg-asip, then copies all client ids to the clipboard
#Needs az login, gh auth login, TF_VAR_location, TF_VAR_subscription_id and ASIP_GITHUB_REPO (owner/repo) set, and the state storage from bootstrap-state.ps1

#Names
$rg = "rg-asip-identity"
$deployIdentity = "id-asip-deploy"
$planIdentity = "id-asip-plan"
$teardownIdentity = "id-asip-teardown"
$planCredentialName = "github-pull-request"
$deployCredentialName = "github-deploy-environment"
$teardownCredentialName = "github-teardown-environment"
$mainCredentialName = "github-main-branch"
$container = "tfstate"
$issuer = "https://token.actions.githubusercontent.com"
$audience = "api://AzureADTokenExchange"

$asipRg = "rg-asip"
$location = $env:TF_VAR_location
if (-not $location) { throw "TF_VAR_location is not set" }

#Repo read at runtime so it never lives in a file
$repo = $env:ASIP_GITHUB_REPO
if ($repo -notmatch "^[^/]+/[^/]+$") { throw "ASIP_GITHUB_REPO must be owner/repo" }

#State storage, names as in backend.tf
$stateRg = "rg-asip-tfstate"
$stateAccount = "asiptfstate86089"

#Stops the script if the last command failed
function Assert-Success($message) {
    if ($LASTEXITCODE -ne 0) { Write-Error $message; exit 1 }
}

#Scopes built in variables so no id is typed or shown
$subscriptionScope = "/subscriptions/$env:TF_VAR_subscription_id"
$containerScope = (az storage account show --name $stateAccount --resource-group $stateRg --query id -o tsv) + "/blobServices/default/containers/$container"
Assert-Success "reading the storage account failed"

#Identity resource group, outside terraform
az group create --name $rg --location $location -o none
Assert-Success "creating the identity resource group failed"

#Plan identity
az identity create --name $planIdentity --resource-group $rg --location $location -o none
Assert-Success "creating the plan identity failed"

#Deploy identity
az identity create --name $deployIdentity --resource-group $rg --location $location -o none
Assert-Success "creating the deploy identity failed"

#Teardown identity
az identity create --name $teardownIdentity --resource-group $rg --location $location -o none
Assert-Success "creating teardown identity failed"

#Subject prefix from GitHub, so immutable subject claims are picked up
$subPrefix = gh api "repos/$repo/actions/oidc/customization/sub" --jq ".sub_claim_prefix"
Assert-Success "reading the OIDC subject prefix failed"
if (-not $subPrefix) { $subPrefix = "repo:$repo" }

#Subjects built from the prefix, exact match, no wildcards
$planSubject = "${subPrefix}:pull_request"
$deploySubject = "${subPrefix}:environment:deploy"
$teardownSubject = "${subPrefix}:environment:teardown"
$mainSubject = "${subPrefix}:ref:refs/heads/main"

#Plan credential, pull requests
az identity federated-credential create --name $planCredentialName --identity-name $planIdentity --resource-group $rg --issuer $issuer --subject $planSubject --audiences $audience -o none
Assert-Success "creating the plan credential failed"

#Plan identity second credential, read-only identity trusted for pushes to main
az identity federated-credential create --name $mainCredentialName --identity-name $planIdentity --resource-group $rg --issuer $issuer --subject $mainSubject --audiences $audience -o none
Assert-Success "creating the main branch credential failed"

#Deploy credential, the deploy environment only
az identity federated-credential create --name $deployCredentialName --identity-name $deployIdentity --resource-group $rg --issuer $issuer --subject $deploySubject --audiences $audience -o none
Assert-Success "creating the deploy credential failed"

#Teardown credential, teardown environment only
az identity federated-credential create --name $teardownCredentialName --identity-name $teardownIdentity --resource-group $rg --issuer $issuer --subject $teardownSubject --audiences $audience -o none
Assert-Success "creating the teardown credential failed"

#Identity principals, never printed
$planPrincipal = az identity show --name $planIdentity --resource-group $rg --query principalId -o tsv
Assert-Success "reading the plan principal id failed"

$deployPrincipal = az identity show --name $deployIdentity --resource-group $rg --query principalId -o tsv
Assert-Success "reading the deploy principal id failed"

$teardownPrincipal = az identity show --name $teardownIdentity --resource-group $rg --query principalId -o tsv
Assert-Success "reading the teardown principal id failed"

#Resource group created here, terraform no longer owns it
az group create --name $asipRg --location $location -o none
Assert-Success "creating resource group failed"

#Group scope for the role assignments, never printed
$asipRgScope = az group show --name $asipRg --query id -o tsv
Assert-Success "getting rg-asip scope failed"
if (-not $asipRgScope) { throw "rg-asip scope is not set" }

#Plan identity, read-only on rg-asip
az role assignment create --assignee-object-id $planPrincipal --assignee-principal-type ServicePrincipal --role "Reader" --scope $asipRgScope -o none
Assert-Success "creating the reader assignment on rg-asip failed"

#Plan identity, reads the subscription security settings
az role assignment create --assignee-object-id $planPrincipal --assignee-principal-type ServicePrincipal --role "Security Reader" --scope $subscriptionScope -o none
Assert-Success "creating the security reader assignment failed"

#Plan identity, state read and lock lease
az role assignment create --assignee-object-id $planPrincipal --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope $containerScope -o none
Assert-Success "creating the plan storage blob contributor assignment failed"

#Deploy identity, contributor on rg-asip only
az role assignment create --assignee-object-id $deployPrincipal --assignee-principal-type ServicePrincipal --role "Contributor" --scope $asipRgScope -o none
Assert-Success "creating the deploy contributor assignment on rg-asip failed"

#Security admin on the subscription, only for the defender plans in defender.tf
az role assignment create --assignee-object-id $deployPrincipal --assignee-principal-type ServicePrincipal --role "Security Admin" --scope $subscriptionScope -o none
Assert-Success "creating the deploy security admin assignment on the subscription failed"

#Deploy identity, state read, write and lock lease
az role assignment create --assignee-object-id $deployPrincipal --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope $containerScope -o none
Assert-Success "creating the deploy storage blob contributor assignment failed"

#Teardown identity, contributor on rg asip only
az role assignment create --assignee-object-id $teardownPrincipal --assignee-principal-type ServicePrincipal --role "Contributor" --scope $asipRgScope -o none
Assert-Success "creating the teardown contributor assignment on rg-asip failed"

#Teardown identity, state read and lock lease
az role assignment create --assignee-object-id $teardownPrincipal --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope $containerScope -o none
Assert-Success "creating the teardown storage blob contributor assignment failed"

#Security admin on the subscription, to teardown defender.tf
az role assignment create --assignee-object-id $teardownPrincipal --assignee-principal-type ServicePrincipal --role "Security Admin" --scope $subscriptionScope -o none
Assert-Success "creating the teardown security admin assignment on the subscription failed"

#Lock the identity group so the pipeline identities cannot be deleted by accident
#Remove before a deliberate teardown of the identities: az lock delete --name lock-asip-identity --resource-group $rg
az lock create --name lock-asip-identity --lock-type CanNotDelete --resource-group $rg -o none
Assert-Success "creating the identity group lock failed"

#Plan client id copy to clipboard only, paste it into the repo secret AZURE_CLIENT_ID
az identity show --name $planIdentity --resource-group $rg --query clientId -o tsv | Set-Clipboard
Assert-Success "copying the plan client id failed"
Read-Host "Plan client id copied, press enter once it is pasted" | Out-Null

#Deploy client id copy to clipboard only, paste it into the deploy environment secret AZURE_CLIENT_ID
az identity show --name $deployIdentity --resource-group $rg --query clientId -o tsv | Set-Clipboard
Assert-Success "copying the deploy client id failed"
Read-Host "Deploy client id copied, press enter once it is pasted" | Out-Null

#Teardown client id copy to clipboard only, paste it into teardown environment secret AZURE_CLIENT_ID
az identity show --name $teardownIdentity --resource-group $rg --query clientId -o tsv | Set-Clipboard
Assert-Success "copying the teardown client id failed"
Read-Host "Teardown client id copied, paste it, then press enter to finish" | Out-Null
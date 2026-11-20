#Bootstrap pipeline identities
#Creates the deploy identity with its credential and roles, and adds the main branch credential to the plan identity
#Needs az login, TF_VAR_location and TF_VAR_subscription_id set, and the plan identity to exist

#Names
$rg = "rg-asip-identity"
$deployIdentity = "id-asip-deploy"
$planIdentity = "id-asip-plan"
$planCredentialName = "github-pull-request"
$deployCredentialName = "github-deploy-environment"
$mainCredentialName = "github-main-branch"
$container = "tfstate"
#State storage, names as in backend.tf
$stateRg = "rg-asip-tfstate"
$stateAccount = "asiptfstate86089"

#Stops the script if the last command failed
function Assert-Success($message) {
    if ($LASTEXITCODE -ne 0) { Write-Error $message; exit 1 }
}

#Plan credential read by name, the base for both subjects
$planSubject = az identity federated-credential show --name $planCredentialName --identity-name $planIdentity --resource-group $rg --query subject -o tsv
Assert-Success "reading plan credential failed"
if (-not $planSubject) { Write-Error "plan credential not found"; exit 1 }

#Deploy identity, uses the location variable already set
az identity create --name $deployIdentity --resource-group $rg --location $env:TF_VAR_location -o none
Assert-Success "identity create failed"

#Deploy subject, ending swapped to the environment
$subject = $planSubject -replace ":pull_request$", ":environment:deploy"

#Deploy credential, exact match, no wildcards
az identity federated-credential create --name $deployCredentialName --identity-name $deployIdentity --resource-group $rg --issuer "https://token.actions.githubusercontent.com" --subject $subject --audiences "api://AzureADTokenExchange" -o none
Assert-Success "creating federated credential failed"

#Main branch subject for the plan identity, ending swapped to the branch
$mainSubject = $planSubject -replace ":pull_request$", ":ref:refs/heads/main"

#Plan identity second credential, read-only identity trusted for pushes to main
az identity federated-credential create --name $mainCredentialName --identity-name $planIdentity --resource-group $rg --issuer "https://token.actions.githubusercontent.com" --subject $mainSubject --audiences "api://AzureADTokenExchange" -o none
Assert-Success "creating the main branch credential failed"

#Client id to clipboard only, never printed
az identity show --name $deployIdentity --resource-group $rg --query clientId -o tsv | Set-Clipboard
Assert-Success "copying the client id failed"

#Identity principal, never printed
$principal = az identity show --name $deployIdentity --resource-group $rg --query principalId -o tsv
Assert-Success "reading the principal id failed"

#Scopes built in variables so no id is typed or shown
$subscriptionScope = "/subscriptions/$env:TF_VAR_subscription_id"
$containerScope = (az storage account show --name $stateAccount --resource-group $stateRg --query id -o tsv) + "/blobServices/default/containers/$container"
Assert-Success "reading the storage account failed"

#Subscription scope, terraform creates rg-asip and the defender setting
az role assignment create --assignee-object-id $principal --assignee-principal-type ServicePrincipal --role "Contributor" --scope $subscriptionScope -o none
Assert-Success "creating the contributor assignment failed"

#Container scope only, state read, write and lock lease
az role assignment create --assignee-object-id $principal --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope $containerScope -o none
Assert-Success "creating storage blob contributor assignment failed"

#Verify, role names only
az role assignment list --assignee $principal --all --query "[].roleDefinitionName" -o tsv
Assert-Success "listing the role assignments failed"
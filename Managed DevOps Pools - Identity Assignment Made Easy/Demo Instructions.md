## Define Variables
```
$ResourceGroupName="mdp-identity-demo-rg"
$Location="CanadaCentral"
$SubscriptionId="$(az account show --query id --output tsv)"

$PoolName="MDP-Identity-Demo"
$DevCenterName="DevOpsPoolDemoDevCenter"
$DevCenterProject="DevOpsPoolProject"

$MdpIdentity="mdp-identity"
$KeyVaultName="wolfgangmdpdemokv" # name must be unique
```

## Create resource group, managed identity, and key vault
```
az group create `
  --name $ResourceGroupName `
  --location $Location

$MdpIdentityPrincipalId=$( `
az identity create `
  --name $MdpIdentity `
  --resource-group $ResourceGroupName `
  --query principalId `
  --output tsv)

az keyvault create `
  --resource-group $ResourceGroupName `
  --name $KeyVaultName `
  --location $Location `
  --enable-rbac-authorization true

az role assignment create `
  --role "Key Vault Secrets Officer" `
  --assignee $MdpIdentityPrincipalId `
  --scope /subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.KeyVault/vaults/$KeyVaultName
```

## Create Managed DevOps Pool
```
$DevCenterId=$( ` 
  az devcenter admin devcenter create `
  --name $DevCenterName `
  --resource-group $ResourceGroupName `
  --location $Location `
  --query id `
  --output tsv)

$DevCenterProjectId=$( `
  az devcenter admin project create `
  --name $DevCenterProject `
  --description "Youtube Dev Center Demo" `
  --resource-group $ResourceGroupName `
  --location $Location `
  --dev-center-id $DevCenterId `
  --query id `
  --output tsv)
```

$SubscriptionId --> replace in identity.json

```
az mdp pool create `
  --name $PoolName `
  --resource-group $ResourceGroupName `
  --location $Location `
  --devcenter-project-id $DevCenterProjectId `
  --maximum-concurrency 1 `
  --agent-profile agent-profile.json `
  --fabric-profile fabric-profile.json `
  --organization-profile organization-profile.json `
  --identity identity.json
```
## Define Variables
```
$ResourceGroupName="mdp-stateful-demo-rg"
$Location="CanadaCentral"

$PoolName="MDP-Stateful-Demo"
$DevCenterName="DevOpsPoolDevCenter"
$DevCenterProject="DevOpsPoolProject"
```

## Create a Managed DevOps Pool with a stateless agent
```
az group create `
  --name $ResourceGroupName `
  --location $Location

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

az mdp pool create `
  --name $PoolName `
  --resource-group $ResourceGroupName `
  --location $Location `
  --devcenter-project-id $DevCenterProjectId `
  --maximum-concurrency 1 `
  --agent-profile agent-profile-stateless.json `
  --fabric-profile fabric-profile.json `
  --organization-profile organization-profile.json    
```

Test the pipeline

## Update pool to use a stateful agent
```
az mdp pool update `
  --name $PoolName `
  --resource-group $ResourceGroupName `
  --devcenter-project-id $DevCenterProjectId `
  --maximum-concurrency 1 `
  --agent-profile agent-profile-stateful.json `
  --fabric-profile fabric-profile.json `
  --organization-profile organization-profile.json    
```
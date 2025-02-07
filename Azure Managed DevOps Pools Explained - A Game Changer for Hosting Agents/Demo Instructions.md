# Register Provider
```
az provider register --namespace Microsoft.DevOpsInfrastructure
az provider register --namespace Microsoft.DevCenter

az provider show --namespace Microsoft.DevOpsInfrastructure -o table
az provider show --namespace Microsoft.DevCenter -o table
```

# Install Azure CLI Extensions
```
az extension add --name devcenter --upgrade
az extension add --name mdp --upgrade
```

# Variables
```
$ResourceGroup="managed-devops-pool-demo"
$Location="CanadaCentral"
$PoolName="ManagedDevOpsPoolDemo"
$DevCenterName="DevOpsPoolDevCenter"
$DevCenterProject="DevOpsPoolProject"
```

# Create Resource Group
```
az group create --name $ResourceGroup --location $Location
```

# Create a dev center
```
az devcenter admin devcenter create `
    --name $DevCenterName `
    --resource-group $ResourceGroup `
    --location $Location
```

# Save the id of the newly created dev center
```
$DevCenterId=$( `
    az devcenter admin devcenter show `
    --name $DevCenterName `
    --resource-group $ResourceGroup `
    --query id -o tsv)
```

# Create a dev center project
```
az devcenter admin project create `
    --name $DevCenterProject `
    --description "Youtube Dev Center Demo" `
    --resource-group $ResourceGroup `
    --location $Location `
    --dev-center-id $DevCenterId
```

# Save the dev center project for use when creating the Managed DevOps Pool
```
$DevCenterProjectId=$( `
    az devcenter admin project show `
    --name $DevCenterProject `
    --resource-group $ResourceGroup `
    --query id -o tsv)
```

# Create the Managed DevOps Pool
```
az mdp pool create `
    --name $PoolName `
    --resource-group $ResourceGroup `
    --location $Location `
    --devcenter-project-id $DevCenterProjectId `
    --maximum-concurrency 1 `
    --agent-profile agent-profile.json `
    --fabric-profile fabric-profile.json `
    --organization-profile organization-profile.json
```
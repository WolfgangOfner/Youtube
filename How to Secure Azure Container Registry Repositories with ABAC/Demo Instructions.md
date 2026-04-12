## Define Variables
```
$AcrName="wolfgangabacdemoacr"
$Location="CanadaCentral"
$ResourceGroupName="abac-demo-rg"
```

## Create ACR
```
az group create `
  --name $ResourceGroupName `
  --location $Location

$AcrId=(az acr create `
    --name $AcrName `
    --resource-group $ResourceGroupName `
    --sku Basic `
    --role-assignment-mode rbac-abac `
    --query id `
    --output tsv)

az acr import --name $AcrName --source docker.io/library/hello-world:latest --image team-a/hello-world:latest --no-wait
az acr import --name $AcrName --source docker.io/library/hello-world:latest --image team-a/byebye-world:latest --no-wait
az acr import --name $AcrName --source docker.io/library/hello-world:latest --image team-b/hello-world:latest --no-wait
```

## ACR Role Assignments
```
$Condition = @'
(
 (
  !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/read'})
  AND
  !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/read'})
 )
 OR 
 (
  @Request[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWithIgnoreCase 'team-a/'
 )
)
'@ -replace "`n", "" -replace "`r", ""

az role assignment create `
    --assignee "demo.user@programmingwithwolfgang.com" `
    --role "Container Registry Repository Writer" `
    --condition "$Condition" `
    --scope $AcrId `
    --description "Read access to specific repositories" `
    --condition-version "2.0"

az role assignment create `
    --assignee "demo.user@programmingwithwolfgang.com" `
    --role "Container Registry Repository Catalog Lister" `
    --scope $AcrId
```

## Test ACR Repository Access
```
az login
az account show --query user.name

az acr repository show-tags `
    --name $AcrName `
    --repository team-a/hello-world

az acr repository list --name $AcrName

az acr repository show-tags `
    --name $AcrName `
    --repository team-b/hello-world
```
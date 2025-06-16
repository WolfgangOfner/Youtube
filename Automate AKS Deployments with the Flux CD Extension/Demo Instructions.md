## Setup
```
az extension add -n k8s-configuration
az extension add -n k8s-extension

az extension update -n k8s-configuration
az extension update -n k8s-extension

az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.KubernetesConfiguration

az provider show -n Microsoft.KubernetesConfiguration -o table
az provider show -n Microsoft.ContainerService -o table
az provider show -n Microsoft.KubernetesConfiguration -o table
```

## Define Variables
```
$ResourceGroupName="flux-gitops"
$Location="CanadaCentral"
$AksName="gitops-demo-aks"
$GitOpsOperatorName="gitopsoperator"
$GitOpsOperatorNamespace="aks-gitops-flux"
$BranchName="gitops-youtube"
```

## Create RG and AKS Cluster
```
az group create `
    --name $ResourceGroupName `
    --location $Location

az aks create `
    --name $AksName `
    --resource-group $ResourceGroupName

az aks get-credentials `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing
```

## Deploy Flux Extension and Agent
connectedClusters if you are using an Arc-enabled cluster

```
az k8s-configuration flux create `
    --cluster-name $AksName `
    --resource-group $ResourceGroupName `
    --name $GitOpsOperatorName `
    --namespace $GitOpsOperatorNamespace `
    --cluster-type managedClusters `
    --scope cluster `
    --url https://github.com/WolfgangOfner/Youtube `
    --branch $BranchName `
    --sync-interval 20s `
    --kustomization name=app path="./Automate AKS Deployments with the Flux CD Extension/App" prune=true

az k8s-configuration flux show `
    --resource-group $ResourceGroupName `
    --cluster-name $AksName `
    --name $GitOpsOperatorName `
    --cluster-type managedClusters

az k8s-configuration flux delete `
    --resource-group $ResourceGroupName `
    --cluster-name $AksName `
    --name $GitOpsOperatorName `
    --cluster-type managedClusters `
    --yes
```

## Deploy with Dependencies
```
az k8s-configuration flux create `
    --cluster-name $AksName `
    --resource-group $ResourceGroupName `
    --name $GitOpsOperatorName `
    --namespace $GitOpsOperatorNamespace `
    --cluster-type managedClusters `
    --scope cluster `
    --url https://github.com/WolfgangOfner/Youtube `
    --branch $BranchName `
    --sync-interval 20s `
    --kustomization name=infrastructure path="/Automate AKS Deployments with the Flux CD Extension/Infrastructure" prune=true `
    --kustomization name=app path="./Automate AKS Deployments with the Flux CD Extension/App" prune=true dependsOn=["infrastructure"]
```

Use a user and key (PAT) to access a private Git repo in Azure DevOps or GitHub

```
[--https-key]
[--https-user]
```
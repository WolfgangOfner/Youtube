## Define Variables
```
$AksName = "automatic-aks"
$Location = "CanadaCentral"
$ResourceGroupName = "aks-automatic-rg"
```

## Create AKS Automatic Cluster
```
az feature register --namespace Microsoft.ContainerService --name AutomaticSKUPreview
az feature register --namespace Microsoft.ContainerService --name DisableSSHPreview
az feature register --namespace Microsoft.ContainerService --name NRGLockdownPreview

az feature show --namespace Microsoft.ContainerService --name AutomaticSKUPreview
az feature show --namespace Microsoft.ContainerService --name DisableSSHPreview
az feature show --namespace Microsoft.ContainerService --name NRGLockdownPreview

az group create `
    --name $ResourceGroupName `
    --location $Location

az aks create `
    --name $AksName `
    --resource-group $ResourceGroupName `
    --sku automatic
```

## Access the Cluster
```
az aks get-credentials `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing

kubelogin convert-kubeconfig -l azurecli
```
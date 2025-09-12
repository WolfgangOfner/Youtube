## Define Variables 
```
$AksName="private-aks-cluster"
$ResourceGroupName="private-cluster-rg"
$Location="CanadaCentral"
```

## Create AKS
```
az group create `
    --name $ResourceGroupName `
    --location $Location

az aks create `
    --name $AksName `
    --resource-group $ResourceGroupName `
    --enable-private-cluster

az aks get-credentials `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing

```
Run command in the Azure Portal

```
kubectl create ns private
```

Run command in terminal

```
kubectl run nginx --image=nginx -n private

az aks command invoke `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --command "kubectl run nginx --image=nginx -n private"

az aks command invoke `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --command "kubectl get pod nginx -n private"
```

## Update existing AKS Cluster

Check configuration in Azure portal

```
az extension add --name aks-preview --upgrade

az aks update  `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --enable-private-cluster

az extension remove --name aks-preview
```
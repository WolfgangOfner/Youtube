## Define Variables
```
$AksName="kubecolor-aks"
$Location="CanadaCentral"
$ResourceGroupName="kubecolor-rg"
```

## Create AKS
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

## Install and configure Kubecolor
```
kubectl get pods -A
kubectl describe pod XXX

winget install --id Kubecolor.kubecolor

$PROFILE
code $PROFILE

Set-Alias -Name kubectl -Value kubecolor

. $PROFILE

kubectl get pods -A
kubectl describe pod XXX
```
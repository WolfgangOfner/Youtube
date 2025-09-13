## Define Variables
```
$AksName="private-aks-cluster"
$ResourceGroupName="private-cluster-rg"
$Location="CanadaCentral"
$AcrName="privateakswolfgang"
$AcrTokenName="DemoToken"
```

## Deploy AKS and ACR
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

az acr create `
    --resource-group $ResourceGroupName `
    --name $AcrName `
    --sku Premium

az acr import `
    --name $AcrName `
    --source docker.io/library/nginx:latest `
    --image nginx
```

Create Token with read permissions and copy the password
Disable public network access for ACR

## Something
```
$AcrTokenPassword=$(`
    az acr token create `
    --name $AcrTokenName `
    --registry $AcrName `
    --scope  _repositories_pull `
    --no-passwords false `
    --query credentials.passwords[0].value `
    -o tsv)

az aks command invoke `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --command "kubectl create ns acr"

az aks command invoke `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --command "kubectl create secret docker-registry tokensecret --docker-server=$AcrName.azurecr.io --docker-username=$AcrTokenName --docker-password=$AcrTokenPassword -n acr"

az aks command invoke `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --command "kubectl apply -f create-pod.yaml -n acr" `
    --file create-pod.yaml

az aks command invoke `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --command "kubectl get pod private-registry -n acr"

az aks command invoke `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --command "kubectl describe pod private-registry -n acr"
```

## ACR Private Endpoint

Create private endpoint in AKS network
If the ACR is in a different VNet --> create a VNet peering between the AKS and ACR VNet + Add AKS VNet to private DNS

```
az aks command invoke `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --command "kubectl delete pod private-registry -n acr"

az aks command invoke `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --command "kubectl apply -f create-pod.yaml -n acr" `
    --file create-pod.yaml
```
## Define Variables
```
$ResourceGroupName="aks-policy-demo"
$AksName="aks-policy"
$Location="canadacentral" # choose a location close to you
```

## Create AKS cluster and enabled Azure Policy Addon
```
az group create `
    --name $ResourceGroupName `
    --location $Location

az aks create `
    --name $AksName `
    --resource-group $ResourceGroupName `
    --enable-addons azure-policy

az aks enable-addons `
    --name $AksName `
    --resource-group $ResourceGroupName `
    --addons azure-policy

az aks show `
    --name $AksName `
    --resource-group $ResourceGroupName `
    --query addonProfiles.azurepolicy
```

## Assign Azure Policy to disallow privileged Containers

Kubernetes cluster should not allow privileged containers

```
az aks get-credentials `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing

kubectl create ns privileged
kubectl apply -f .\privileged-pod.yaml -n privileged
kubectl apply -f .\non-privileged-pod.yaml -n privileged
kubectl get pod -n privileged
```

Every 15 minutes, the add-on calls for a full scan of the cluster. 

## Check the Logs 
```
kubectl get pods -n kube-system
kubectl logs azure-policy-86d4c7864f-v4j56 -n kube-system

kubectl get pods -n gatekeeper-system
kubectl logs gatekeeper-controller-6d4cc8855-49n7k -n gatekeeper-system
```

## Assign Azure Policy to enforce Image Cleaner 
```
Azure Kubernetes Service Clusters should enable Image Cleaner
```

## Trigger the Policy Evaluation
```
az policy state trigger-scan `
    --resource-group $ResourceGroupName
```

Understand Your AKS Spending with the Cost Analysis Add-on

az aks create / update `
    --resource-group <MyResourceGroup> `
    --name <MyAksName> `
    --enable-cost-analysis

AKS must be Standard or Premium Tier
Must be EA or MCA (Microsoft Customer Agreement)
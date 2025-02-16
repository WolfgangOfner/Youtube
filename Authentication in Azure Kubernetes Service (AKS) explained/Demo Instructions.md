# Logout all users

## Define Variables for AKS with Local Authentication
```
$AksLocalAuthenticationName="aks-local"
$Location="CanadaCentral"
$ResourceGroupNameLocalAuthentication="aks-local-authentication"
```

## Create AKS
```
az group create --name $ResourceGroupNameLocalAuthentication --location $Location
az aks create --name $AksLocalAuthenticationName --resource-group $ResourceGroupNameLocalAuthentication

az aks get-credentials --resource-group $ResourceGroupNameLocalAuthentication --name $AksLocalAuthenticationName --overwrite-existing
kubectl create ns read
kubectl config set-context --current --namespace=read
kubectl run nginx --image=nginx
kubectl get pods

nano ~/.kube/config
```

## Define Variables for AKS with Entra ID Authentication and K8s RBAC
```
$AksEntraAuthenticationK8sRbacName="aks-entra-k8s-rbac"
$EntraAdminGroupId="54b09e87-0f09-4bd8-b399-f28986ac6c03" # replace with your group id, must be a group not a user, user won't cause an error message but access won't work
$EntraReaderGroupId="24975d09-19e9-47a5-aa3b-e952c693c016" # replace with your group id
$Location="CanadaCentral"
$ResourceGroupNameK8sRbac="aks-entra-authentication-k8s-rbac"
$SubscriptionId="e347e896-c1d2-4aea-b63d-2c7f5f6acc7e"
```

## Create AKS
```
az group create --name $ResourceGroupNameK8sRbac --location $Location 
az aks create `
    --name $AksEntraAuthenticationK8sRbacName `
    --resource-group $ResourceGroupNameK8sRbac `
    --enable-aad `
    --aad-admin-group-object-ids $EntraAdminGroupId

az aks get-credentials `
    --resource-group $ResourceGroupNameK8sRbac `
    --name $AksEntraAuthenticationK8sRbacName `
    --overwrite-existing

kubelogin convert-kubeconfig -l azurecli
kubectl create ns read
kubectl config set-context --current --namespace=read
kubectl run nginx --image=nginx
kubectl get pods

kubectl apply -f reader-role.yaml
kubectl apply -f reader-role-binding.yaml
```

Assign Azure Kubernetes Service Cluster User Role to reader group

```
az role assignment create `
    --role "Azure Kubernetes Service Cluster User Role" `
    --assignee $EntraReaderGroupId `
    --scope /subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupNameK8sRbac/providers/Microsoft.ContainerService/managedClusters/$AksEntraAuthenticationK8sRbacName
```

Delete .kube config to avoid chaching problems
Login with reader user

```
az login 

az aks get-credentials `
    --resource-group $ResourceGroupNameK8sRbac `
    --name $AksEntraAuthenticationK8sRbacName `
    --overwrite-existing
kubelogin convert-kubeconfig -l azurecli

kubectl get ns
kubectl get all -n read
kubectl delete pod nginx -n read
```

## Define Variables for AKS with Entra ID Authentication and Azure RBAC
```
$AksEntraAuthenticationAzureRbacName="aks-entra-azure-rbac"
$Location="CanadaCentral"
$ResourceGroupNameAzureRbac="aks-entra-authentication-azure-rbac"
$SubscriptionId="e347e896-c1d2-4aea-b63d-2c7f5f6acc7e"
```

## Create AKS
```
az group create --name $ResourceGroupNameAzureRbac --location $Location
az aks create `
    --name $AksEntraAuthenticationAzureRbacName `
    --resource-group $ResourceGroupNameAzureRbac `
    --enable-aad `
    --enable-azure-rbac
```

Add Azure Kubernetes Service RBAC Cluster Admin to your user in the Azure portal (only for demo, could also be done via Azure CLI)

```
az aks get-credentials `
    --resource-group $ResourceGroupNameAzureRbac `
    --name $AksEntraAuthenticationAzureRbacName `
    --overwrite-existing
kubelogin convert-kubeconfig -l azurecli

kubectl create ns read
kubectl config set-context --current --namespace=read
kubectl run nginx --image=nginx
kubectl get pods

az role assignment create `
    --role "Azure Kubernetes Service Cluster User Role" `
    --assignee $EntraReaderGroupId `
    --scope /subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupNameAzureRbac/providers/Microsoft.ContainerService/managedClusters/$AksEntraAuthenticationAzureRbacName

az role assignment create `
    --role "Azure Kubernetes Service RBAC Reader" `
    --assignee $EntraReaderGroupId `
    --scope /subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupNameAzureRbac/providers/Microsoft.ContainerService/managedClusters/$AksEntraAuthenticationAzureRbacName/namespaces/read

az role assignment list `
    --assignee $EntraReaderGroupId `
    --scope /subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupNameAzureRbac/providers/Microsoft.ContainerService/managedClusters/$AksEntraAuthenticationAzureRbacName/namespaces/read
```

Delete .kube config to avoid chaching problems
Login with reader user

```
az aks get-credentials `
    --resource-group $ResourceGroupNameAzureRbac `
    --name $AksEntraAuthenticationAzureRbacName `
    --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
```
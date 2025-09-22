$AksName = "managed-namespace-aks"
$Location = "CanadaCentral"
$ResourceGroupName = "managed-namespace-rg"

$NamespaceName = "managed-ns"
$Labels = "owner=wolfgang", "project=youtube"
$Annotations = "department=demo", "CostCenter=wolfgang"

$SubscriptionId=$(az account show --query id --output tsv)
$AdminUser=$(az account show --query "user.name" -o tsv)
$DemoUser="demo.user@programmingwithwolfgang.com" # change email to your demo user or group

az extension add --name aks-preview
az extension update --name aks-preview

az feature register --namespace Microsoft.ContainerService --name ManagedNamespacePreview
az feature show --namespace Microsoft.ContainerService --name ManagedNamespacePreview
az provider register --namespace Microsoft.ContainerService

az group create `
    --name $ResourceGroupName `
    --location $Location

az aks create `
    --name $AksName `
    --resource-group $ResourceGroupName `
    --enable-aad `
    --enable-azure-rbac

az aks namespace add `
    --name $NamespaceName `
    --cluster-name $AksName `
    --resource-group $ResourceGroupName `
    --cpu-request 1000m `
    --cpu-limit 2000m `
    --memory-request 512Mi `
    --memory-limit 1Gi `
    --labels $Labels `
    --annotations $Annotations `
    --ingress-policy AllowSameNamespace `
    --egress-policy AllowAll `
    --adoption-policy Never `
    --delete-policy Keep

az role assignment create `
    --role "Azure Kubernetes Service RBAC Cluster Admin" `
    --assignee $AdminUser `
    --scope /subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/Microsoft.ContainerService/managedClusters/$AksName

az aks get-credentials `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing

kubelogin convert-kubeconfig -l azurecli

kubectl get ns
kubectl run nginx --image=nginx -n managed-ns

$NamespaceId=$(`
    az aks namespace show `
    --name $NamespaceName `
    --cluster-name $AksName `
    --resource-group $ResourceGroupName `
    --query id `
    --output tsv)

az role assignment create `
    --assignee $DemoUser `
    --role "Azure Kubernetes Service Namespace User" `
    --scope $NamespaceId

az role assignment create `
    --assignee $DemoUser `
    --role "Azure Kubernetes Service RBAC Writer" `
    --scope $NamespaceId

az logout
az account clear
az login

az aks namespace get-credentials `
    --name $NamespaceName `
    --resource-group $ResourceGroupName `
    --cluster-name $AksName `
    --overwrite-existing

kubelogin convert-kubeconfig -l azurecli

kubectl apply -f .\deployment.yml

kubectl get pods -n $NamespaceName
kubectl get deployment -n $NamespaceName
kubectl describe deployment nginx-deployment -n $NamespaceName

kubectl get replicaset -n $NamespaceName
kubectl describe replicaset nginx-deployment-5bf5857f5d -n $NamespaceName
kubectl get quota -n $NamespaceName
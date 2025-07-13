## Define Variables
```
$ResourceGroupName="argocd-demo"
$Location="CanadaCentral"
$AksName="argocd-aks"
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

## Deploy ArgoCD and access ArgoCD UI
```
kubectl create ns argocd

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm install argo-cd argo/argo-cd --version 8.1.2 -n argocd

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

$Password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}")
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Password))

kubectl port-forward service/argo-cd-argocd-server -n argocd 8080:443
```

## Deploy Helm Charts
```
redis-helm
default
sync policy autoamtic
self heal
prune resources
auto-create namespace

https://charts.bitnami.com/bitnami
redis
21.2.7

cluster: local

new project:
my-project
Source Repositories
Destinations
Cluster Resources Allow List

https://github.com/WolfgangOfner/Youtube.git
argo-cd-helm
Deploying Apps with Helm Charts in ArgoCD UI/charts/argocdhelm

helm ls -A
```

## Interesting fact about ArgoCD and Helm
When deploying a Helm application Argo CD is using Helm only as a template mechanism. It runs helm template and then deploys the resulting manifests on the cluster instead of doing helm install. This means that you cannot use any Helm command to view/verify the application. It is fully managed by Argo CD. Note that Argo CD supports natively some capabilities that you might miss in Helm (such as the history and rollback commands).

This decision was made so that Argo CD is neutral to all manifest generators.
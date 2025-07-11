## Define Variables
```
$ResourceGroupName="argocd-demo"
$Location="CanadaCentral"
$AksName="argocd-aks"
```

## Create RG, AKS Cluster and deploy ArgoCD Helm Chart
```
az group create `
    --name $ResourceGroupName `
    --location $Location

az aks create `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --location $Location

az aks get-credentials `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing

kubectl create ns argocd

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm install argo-cd argo/argo-cd --version 8.1.2 -n argocd
```

## Access ArgoCD UI
```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

$Password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}")
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Password))

kubectl port-forward service/argo-cd-argocd-server -n argocd 8080:443
```

## Create ADO PAT and connect ADO Repo to ArgoCD
Create PAT and add repository in ArgoCD UI with your username and PAT
```
https://ProgrammingWithWolfgang@dev.azure.com/ProgrammingWithWolfgang/Youtube/_git/Youtube
```

## Create GitHub PAT and connect ADO Repo to ArgoCD
Create PAT and add repository in ArgoCD UI with your username and PAT
```
https://github.com/WolfgangOfner/private-gitops-flux2-kustomize-helm-mt.git
```
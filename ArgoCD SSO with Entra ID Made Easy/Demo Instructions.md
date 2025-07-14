## Define Variables
```
$ResourceGroupName="argocd-demo"
$Location="CanadaCentral"
$AksName="argocd-aks"
$TenantId="$(az account show --query tenantId --output tsv)"
```

## Create RG and AKS Cluster
```
az group create `
    --name $ResourceGroupName `
    --location $Location

az aks create `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --location $Location `
    --enable-oidc-issuer `
    --enable-workload-identity 

$AksOidcIssuer="$(az aks show `
    --name $AksName `
    --resource-group $ResourceGroupName `
    --query oidcIssuerProfile.issuerUrl `
    --output tsv)"

az aks get-credentials `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing

kubectl config set-context --current --namespace=argocd
```
Install Bicep https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install

```
az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file .\main-sso.bicep

kubectl patch service argocd-server --patch-file .\service-argocd-server-patch.json

kubectl get service argocd-server
```

copy external IP of service

```
$AksOidcIssuer: XXX
$TenantId: XXX
External Service URL: XXX
```

## Register Application in Entra
Azure Portal --> Microsoft Entra ID --> App registrations --> + New registration

Provide Name
Redirect URL: Web + https://<EXTERNAL_IP_OF_SERVICE>/auth/callback
Create

Copy Application (client) ID: XXX

Authentication --> + Add a platform --> Mobile and Desktop Application --> 
http://localhost:8085/auth/callback (used by argocd cli)

Certificates & secrets --> Federated credentials --> + Add credential
Kubernetes accessing Azure resources --> $AksOidcIssuer + argocd (namespace) + argocd-server (serviceaccount)

kubectl get serviceaccount (check for name of argocd-server service account)

Token Configuration --> + Add groups claim --> Groups assigned to the application

API Permissions --> Check that Microsoft Graph User.Read permission is there --> Grand admin consent

Microsoft Entra ID --> Enterprise applications (same name as App) --> Users and groups --> + Add user/group

replace values in main-sso.bicep

```
az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file .\main-sso.bicep
```

## Check Label, Annotation and ConfigMap for ArgoCD (without extension)
```
kubectl get pods
kubectl get pod argocd-server-696f9d698c-ccdxq --show-labels
kubectl describe serviceaccount argocd-server
```
Add the label and annotation if they are missing
```
kubectl label pod argocd-repo-server-XXX "azure.workload.identity/use=true"
kubectl annotate serviceaccount argocd-repo-server azure.workload.identity/client-id="$AppClientId"

kubectl get configmap argocd-cm -o yaml
kubectl get configmap argocd-rbac-cm -o yaml
```
## Define Variables
```
$ResourceGroupName="argocd-demo"
$Location="CanadaCentral"
$AksName="argocd-aks"

$ArgoCdNamespace="argocd"
$UserAssignedIdentityName="argocd-workloadIdentity-UserAssignedIdentity"
$FederatedIdentityCredentialName="argocd-federateIdentitiy"
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

az identity create `
    --name $UserAssignedIdentityName `
    --resource-group $ResourceGroupName `
    --location $Location

$UserAssignedClientId="$(az identity show `
    --resource-group $ResourceGroupName `
    --name $UserAssignedIdentityName `
    --query 'clientId' `
    --output tsv)"

az aks get-credentials `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing
```

## Add Identity to your ADO Organization and assign permissions to read the Repo
Invite "user" $UserAssignedIdentityName

## Deploy ArgoCD AKS Extension with Identity
replace aks name (if you changed it) and $UserAssignedClientId in main-workload-identity.bicep

```
az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file .\main-workload-identity.bicep

kubectl config set-context --current --namespace=$ArgoCdNamespace
```

check if label and annotations are already set

```
kubectl get pods
kubectl describe pod argocd-repo-server-argocd-repo-server-76f698bfd9-p6xjf
```

If the label is missing, add it to pod or pod template in deployment

```
kubectl label pod argocd-repo-server-XXX "azure.workload.identity/use=true"

kubectl get serviceaccount
kubectl describe serviceaccount argocd-repo-server
```
If annotation is missing, add it to the serviceaccount
```
kubectl annotate serviceaccount argocd-repo-server azure.workload.identity/client-id="$UserAssignedClientId"
```

Create a federated identitiy to enable workload identitiy to get Entra token

```
az identity federated-credential create `
    --name $FederatedIdentityCredentialName `
    --identity-name $UserAssignedIdentityName `
    --resource-group $ResourceGroupName `
    --issuer $AksOidcIssuer `
    --subject system:serviceaccount:"$ArgoCdNamespace":"argocd-repo-server"
```

## Access ArgoCD UI and add Repository using Workload Identitiy
```
$Password=$(kubectl get secret argocd-initial-admin-secret -o jsonpath="{.data.password}")
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Password))

kubectl port-forward service/argocd-server 8080:443
```
Settings --> Repositories --> + Connect Repo --> 
- via HTTP/HTTPs
- Type = git
- Repository URL = https://ProgrammingWithWolfgang@dev.azure.com/ProgrammingWithWolfgang/Youtube/_git/Youtube (replace with your URL)
- Use Azure Workload Identity = true

Add new App with this repo
```
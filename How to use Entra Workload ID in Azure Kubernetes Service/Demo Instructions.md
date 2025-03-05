## Define Variables
```
$ResourceGroupName="WorkloadIdentity-rg"
$AksName="WorkloadIdentityCluster"
$Location="canadacentral" # choose a location close to you
$KeyVaultName="workloadidentitywolfgang" # name must be unique
$KeyVaultSecret="WorkloadSecret"
$SubscriptionId="$(az account show --query id --output tsv)"

$ServiceAccountNamespace="workload-identity"
$ServiceAccountName="workload-identity-sa"
$UserAssignedIdentityName="workloadIdentityUserAssignedIdentity"
$FederatedIdentityCredentialName="federateIdentitiy"
```

## Create Azure Key Vault and AKS cluster
```
az group create `
    --name $ResourceGroupName `
    --location $Location

az keyvault create `
    --resource-group $ResourceGroupName `
    --name $KeyVaultName `
    --location $Location `
    --enable-rbac-authorization true

az role assignment create `
    --role "Key Vault Administrator" `
    --assignee wolfgang@programmingwithwolfgang.com `
    --scope /subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.KeyVault/vaults/$KeyVaultName

az keyvault secret set `
    --vault-name $KeyVaultName `
    --name $KeyVaultSecret `
    --value 'This is a secret!'

$KeyVaultUrl="$(az keyvault show `
    --resource-group $ResourceGroupName `
    --name $KeyVaultName `
    --query properties.vaultUri `
    --output tsv)"

az aks create `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --location $Location `
    --enable-oidc-issuer `
    --enable-workload-identity         
```

## Configer Oidc Access to Key Vault
```
$AksOidcIssuer="$(az aks show `
    --name $AksName `
    --resource-group $ResourceGroupName `
    --query oidcIssuerProfile.issuerUrl `
    --output tsv)"

az identity create `
    --name $UserAssignedIdentityName `
    --resource-group $ResourceGroupName `
    --location $Location `
    --subscription $SubscriptionId

$UserAssignedClientId="$(az identity show `
    --resource-group $ResourceGroupName `
    --name $UserAssignedIdentityName `
    --query 'clientId' `
    --output tsv)"

az role assignment create `
    --role "Key Vault Secrets User" `
    --assignee $UserAssignedClientId `
    --scope /subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.KeyVault/vaults/$KeyVaultName
```

## Create Service Account

```
az aks get-credentials `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing

kubectl create ns workload-identity
kubectl config set-context --current --namespace=workload-identity

$serviceAccountWorkloadIdentitiy = @"
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: $UserAssignedClientId
  name: $ServiceAccountName
  namespace: $ServiceAccountNamespace
"@

$serviceAccountWorkloadIdentitiy | kubectl apply -f -

az identity federated-credential create `
    --name $FederatedIdentityCredentialName `
    --identity-name $UserAssignedIdentityName `
    --resource-group $ResourceGroupName `
    --issuer $AksOidcIssuer `
    --subject system:serviceaccount:${ServiceAccountNamespace}:${ServiceAccountName}
```

It takes a few seconds for the federated identity credential to propagate after it is added.

## Deploy Pod to test the Key Vault access
Ensure that the application pods using workload identity include the label azure.workload.identity/use: "true" in the pod spec. 

```
$podWorkloadIdentitiy = @"
apiVersion: v1
kind: Pod
metadata:
  name: workload-identity-test
  namespace: $ServiceAccountNamespace
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: $ServiceAccountName
  containers:
    - image: ghcr.io/azure/azure-workload-identity/msal-go
      name: oidc
      env:
      - name: KEYVAULT_URL
        value: $KeyVaultUrl
      - name: SECRET_NAME
        value: $KeyVaultSecret
  nodeSelector:
    kubernetes.io/os: linux
"@

$podWorkloadIdentitiy | kubectl apply -f -
kubectl get pods
kubectl logs workload-identity-test
```


Using the Azure Key Vault provider for Secrets Store CSI Driver in an Azure Kubernetes Service (AKS) offers several advantages over accessing the Key Vault directly from within your application:

Simplified Secret Management: The Secrets Store CSI Driver allows you to mount secrets, keys, and certificates directly into your pods as volumes. This simplifies the management of sensitive data by abstracting the complexity of accessing and handling secrets within your application code1.

Enhanced Security: By using the CSI Driver, secrets are managed at the infrastructure level, reducing the risk of exposing sensitive data in your application code. The secrets are mounted directly into the pod's file system, ensuring they are only accessible to the specific pod1.

Automatic Synchronization: The CSI Driver supports automatic synchronization with Kubernetes secrets. This means any updates to the secrets in Azure Key Vault are automatically reflected in the Kubernetes secrets, ensuring your application always has the latest secret values without requiring manual intervention1.

Pod Portability: The SecretProviderClass Custom Resource Definition (CRD) supports pod portability, allowing you to define how secrets are fetched and mounted in a declarative manner. This makes it easier to manage secrets across different environments and clusters1.

Auto-Rotation of Secrets: The CSI Driver supports the auto-rotation of secrets, ensuring that your application always uses the most up-to-date secrets without requiring restarts or redeployments1.
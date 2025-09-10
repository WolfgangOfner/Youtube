## Define Variables
```
$ResourceGroupName="Key-Vault-Secret-Demo-rg"
$AksName="key-vault-aks"
$Location="canadacentral" # choose a location close to you

$K8sNamespace="keyvault-secret"
$ServiceAccountName="key-vault-secret-sa"
$UserAssignedIdentityName="keyVaultUserAssignedIdentity"
$FederatedIdentityCredentialName="federateIdentitiy"

$KeyVaultName="kvsecretsyncwolfgang" # name must be unique
$KeyVaultSecret="MySecret"
$SubscriptionId="$(az account show --query id --output tsv)"
$TenantId="$(az account show --query tenantId --output tsv)"
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

kubectl create ns $K8sNamespace
kubectl config set-context --current --namespace=$K8sNamespace

$ServiceAccountWorkloadIdentitiy = @"
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: $UserAssignedClientId
  name: $ServiceAccountName
  namespace: $K8sNamespace
"@

$ServiceAccountWorkloadIdentitiy | kubectl apply -f -

az identity federated-credential create `
    --name $FederatedIdentityCredentialName `
    --identity-name $UserAssignedIdentityName `
    --resource-group $ResourceGroupName `
    --issuer $AksOidcIssuer `
    --subject system:serviceaccount:${K8sNamespace}:${ServiceAccountName}
```

It takes a few seconds for the federated identity credential to propagate after it is added.

## Deploy Pod to test the Key Vault access
```
az aks enable-addons `
    --addons azure-keyvault-secrets-provider `
    --name $AksName `
    --resource-group $ResourceGroupName

kubectl get pods -n kube-system

$SecretProviderClass=@"
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-kv-secret-provider
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    clientID: $UserAssignedClientId
    keyvaultName: $KeyVaultName
    cloudName: ""
    objects:  |
      array:
        - |
          objectName: $KeyVaultSecret
          objectType: secret              # object types: secret, key, or cert
          objectVersion: ""               # [OPTIONAL] object versions, default to latest if empty
    tenantId: $TenantId
"@

$SecretProviderClass | kubectl apply -f -

$BusyboxPod=@"
kind: Pod
apiVersion: v1
metadata:
  name: busybox-secrets-store
spec:
  serviceAccountName: $ServiceAccountName
  containers:
    - name: busybox
      image: busybox:1.37
      command:
        - "/bin/sleep"
        - "10000"
      volumeMounts:
      - name: secrets-store01-inline
        mountPath: "/mnt/secrets-store"
        readOnly: true
  volumes:
    - name: secrets-store01-inline
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "azure-kv-secret-provider"
"@

$BusyboxPod | kubectl apply -f -

kubectl get pods

kubectl exec busybox-secrets-store -- ls /mnt/secrets-store/
kubectl exec busybox-secrets-store -- cat /mnt/secrets-store/MySecret
```

## Create Kubernetes Secrets from Key Vault Secrets
```
$SecretProviderClass=@"
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-kv-secret-provider
  labels:
    azure.workload.identity/use: "true"
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    clientID: $UserAssignedClientId
    keyvaultName: $KeyVaultName
    cloudName: ""
    objects:  |
      array:
        - |
          objectName: $KeyVaultSecret
          objectType: secret              # object types: secret, key, or cert
          objectVersion: ""               # [OPTIONAL] object versions, default to latest if empty
    tenantId: $TenantId
  secretObjects:
  - secretName: newsecret
    data:
    - key: $KeyVaultSecret
      objectName: $KeyVaultSecret
    type: Opaque 
"@

$SecretProviderClass | kubectl apply -f -

kubectl delete pod busybox-secrets-store

$BusyboxPod | kubectl apply -f -

kubectl get pods

kubectl get secrets
kubectl describe secret newsecret

kubectl get secret newsecret -o jsonpath='{.data}'
```

## Configure Secret Rotation
```
az aks addon update `
    --addon azure-keyvault-secrets-provider `
    --name $AksName `
    --resource-group $ResourceGroupName `
    --enable-secret-rotation `
    --rotation-poll-interval 10s

az keyvault secret set `
    --vault-name $KeyVaultName `
    --name $KeyVaultSecret `
    --value 'This is an updated secret!'

kubectl exec busybox-secrets-store -- cat /mnt/secrets-store/MySecret

kubectl get secret newsecret -o jsonpath='{.data}'
```
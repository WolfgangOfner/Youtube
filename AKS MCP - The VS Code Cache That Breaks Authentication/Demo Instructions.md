## Define Variables
```
$AksMcpHelmDeploymentName="aks-mcp"
$AksMcpNamespace="aks-mcp"
$AksMcpOauthDisplayNameOld="AKS-MCP-OAuth"
$AksMcpOauthDisplayName="AKS-MCP-OAuth-New"
$TenantId=(az account show --query tenantId -o tsv)
```

## Create and configure App Registration
```powershell
kubectl port-forward svc/$AksMcpHelmDeploymentName 8000:8000 -n $AksMcpNamespace

$EntraAppClientIdOld=$(`
  az ad app list `
  --display-name "$AksMcpOauthDisplayNameOld" `
  --query "[0].appId" `
  -o tsv)

az ad app delete --id $EntraAppClientIdOld

Write-Host $EntraAppClientIdOld

az ad app create `
  --display-name "$AksMcpOauthDisplayName" `
  --public-client-redirect-uris "http://localhost:8000/oauth/callback"

$EntraAppClientId=$(`
  az ad app list `
  --display-name "$AksMcpOauthDisplayName" `
  --query "[0].appId" `
  -o tsv)

# 797f4846-ba00-4fd7-ba43-dac1f8f63013 = well-known appId for the "Azure Service Management" API
# 41094075-9dad-400e-a0bd-54e686782033 = permission id for its "user_impersonation" delegated scope
az ad app permission add `
  --id $EntraAppClientId `
  --api 797f4846-ba00-4fd7-ba43-dac1f8f63013 `
  --api-permissions 41094075-9dad-400e-a0bd-54e686782033=Scope

az ad sp create --id $EntraAppClientId

$EntraAppObjectId=$(`
  az ad sp list `
  --filter "appId eq '$EntraAppClientId'" `
  --query "[0].id" `
  -o tsv)

az ad app permission grant `
  --id $EntraAppClientId `
  --api 797f4846-ba00-4fd7-ba43-dac1f8f63013 `
  --scope user_impersonation

az ad app permission admin-consent --id $EntraAppClientId

az ad sp update `
  --id $EntraAppObjectId `
  --set appRoleAssignmentRequired=true
```

## Configure MCP-Server to use OAuth
```powershell
cd aks-mcp/chart

helm upgrade $AksMcpHelmDeploymentName . `
  --namespace $AksMcpNamespace `
  --reuse-values `
  --set oauth.enabled=true `
  --set oauth.tenantId=$TenantId `
  --set oauth.clientId=$EntraAppClientId `
  --set "oauth.redirectURIs={http://127.0.0.1:33418/}"

kubectl get pods -n $AksMcpNamespace 
kubectl port-forward svc/$AksMcpHelmDeploymentName 8000:8000 -n $AksMcpNamespace
```
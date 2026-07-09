## Define Variables
```
$AksMcpHelmDeploymentName="aks-mcp"
$AksMcpNamespace="aks-mcp"
$AksMcpOauthDisplayName="AKS-MCP-OAuth"

$TenantId=(az account show --query tenantId -o tsv)
$AuthenticatedUser="wolfgang@programmingwithwolfgang.com"
```

## Create and configure App Registration
```powershell
cd .\aks-mcp\chart\

helm upgrade $AksMcpHelmDeploymentName . `
  --namespace $AksMcpNamespace `
  --reuse-values `
  --set "security.allowedHosts={localhost}"

kubectl port-forward svc/$AksMcpHelmDeploymentName 8000:8000 -n $AksMcpNamespace

az ad app create `
  --display-name $AksMcpOauthDisplayName `
  --public-client-redirect-uris "http://localhost:8000/oauth/callback"

$EntraAppClientId=$(`
  az ad app list `
  --display-name $AksMcpOauthDisplayName `
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

$UserObjectId=$(`
  az ad user show `
  --id $AuthenticatedUser `
  --query id `
  -o tsv)

$body = @{
  principalId = $UserObjectId
  resourceId  = $EntraAppObjectId
  appRoleId   = "00000000-0000-0000-0000-000000000000"
} | ConvertTo-Json -Compress

# "00000000-0000-0000-0000-000000000000"  # default/no-role app role assignment

$bodyFile = "$env:TEMP\assign_body.json"
$body | Out-File -FilePath $bodyFile -Encoding utf8 -NoNewline

az rest --method POST `
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/$EntraAppObjectId/appRoleAssignedTo" `
  --body "@$bodyFile" --headers "Content-Type=application/json"
```

## Configure MCP-Server to use OAuth
```powershell
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
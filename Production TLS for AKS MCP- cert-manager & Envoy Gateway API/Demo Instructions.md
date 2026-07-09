## Define Variables
```powershell
$AksName="aks-mcp-aks"
$ResourceGroupName="aks-mcp-rg"

$AksMcpHelmDeploymentName="aks-mcp"
$AksMcpNamespace="aks-mcp"
$AksMcpUrl="aks-mcp.programmingwithwolfgang.com"
$AksMcpOauthDisplayName="AKS-MCP-OAuth-New"

$GatewayNamespace="envoy-gateway"
$GatewayName="gateway"

$ClusterIssuerName="letsencrypt"
$CertManagerManagedIdentityName="cert-manager"
$CertManagerServiceAccountName="cert-manager"
$CertManagerNamespace="cert-manager"

$DnsZoneName="programmingwithwolfgang.com"
$DnsSubscriptionName="ProgrammingWithWolfgang"
$DnsSubscriptionId=$(az account show --subscription "$DnsSubscriptionName" --query id --output tsv)
$DnsResourceGroup="ProgrammingWithWolfgang"
```

## Install and configure cert-manager
```powershell
helm repo add jetstack https://charts.jetstack.io --force-update
helm install `
  cert-manager jetstack/cert-manager `
  --namespace $CertManagerNamespace `
  --create-namespace `
  --version v1.20.3 `
  --set config.enableGatewayAPI=true `
  --set crds.enabled=true `
  --set-string podLabels."azure\.workload\.identity/use"=true `
  --set-string serviceAccount.labels."azure\.workload\.identity/use"=true `
  --set config.enableGatewayAPIListenerSet=true `
  --set config.featureGates.ListenerSets=true

az identity create `
  --name $CertManagerManagedIdentityName `
  --resource-group $ResourceGroupName

$CertManagerManagedIdentityClientId=$(`
  az identity show `
  --name $CertManagerManagedIdentityName `
  --resource-group $ResourceGroupName `
  --query 'clientId' `
  --output tsv)

az role assignment create `
    --role "DNS Zone Contributor" `
    --assignee $CertManagerManagedIdentityClientId `
    --scope $(`
        az network dns zone show `
        --name $DnsZoneName `
        --resource-group $DnsResourceGroup `
        --subscription $DnsSubscriptionName `
        --query id `
        --output tsv)

$AksOidcIssuer="$(`
  az aks show `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --query "oidcIssuerProfile.issuerUrl" `
  --output tsv)"

az identity federated-credential create `
  --name "cert-manager" `
  --identity-name $CertManagerManagedIdentityName `
  --resource-group $ResourceGroupName `
  --issuer $AksOidcIssuer `
  --subject "system:serviceaccount:${CertManagerNamespace}:${CertManagerServiceAccountName}"

$ClusterIssuer = @"
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: $ClusterIssuerName
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory # production endpoint
    # server: https://acme-staging-v02.api.letsencrypt.org/directory # staging endpoint
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-private-key
    solvers:
      - dns01:
          azureDNS:
            hostedZoneName: $DnsZoneName
            resourceGroupName: $DnsResourceGroup
            subscriptionID: $DnsSubscriptionId
            environment: AzurePublicCloud
            managedIdentity:
              clientID: $CertManagerManagedIdentityClientId
"@

$ClusterIssuer | kubectl apply -f -

kubectl get ClusterIssuer -o yaml
```

## Configure the Gateway API
```powershell
$ListenerSet = @"
apiVersion: gateway.networking.k8s.io/v1
kind: ListenerSet
metadata:
  name: aks-mcp-listener
  namespace: $AksMcpNamespace
  annotations:
    cert-manager.io/cluster-issuer: $ClusterIssuerName
spec:
  parentRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: $GatewayName
    namespace: $GatewayNamespace
  listeners:
  - name: https-mcp
    hostname: $AksMcpUrl
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
        - name: "mcp-tls-secret"
    allowedRoutes:
      namespaces:
        from: All
"@

$ListenerSet | kubectl apply -f -

$HttpRoute = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: aks-mcp-route
  namespace: $AksMcpNamespace
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: ListenerSet
    name: aks-mcp-listener
  hostnames:
  - $AksMcpUrl
  rules:
  - backendRefs:
    - name: $AksMcpHelmDeploymentName
      port: 8000
"@

$HttpRoute | kubectl apply -f -

$EntraAppClientId=$(`
  az ad app list `
  --display-name $AksMcpOauthDisplayName `
  --query "[0].appId" `
  -o tsv)

az ad app update `
  --id $EntraAppClientId `
  --public-client-redirect-uris "https://$AksMcpUrl/oauth/callback"

cd aks-mcp/chart

helm upgrade $AksMcpHelmDeploymentName . `
  --namespace $AksMcpNamespace `
  --reuse-values `
  --set "security.allowedHosts={$AksMcpUrl}" `
  --set "oauth.externalURL=https://$AksMcpUrl" `
  --set "oauth.redirectURIs={http://127.0.0.1:33418/,https://$AksMcpUrl/oauth/callback}"

kubectl get pods -n $AksMcpNamespace
```

Using the MCP-Server, tell me what namespaces the cluster has.
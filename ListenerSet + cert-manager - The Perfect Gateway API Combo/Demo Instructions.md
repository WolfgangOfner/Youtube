## Define Variables
```
$AksName="listenerset-https-aks"
$Location="CanadaCentral"
$ResourceGroupName="listenerset-https-rg"

$GatewayNamespace="envoy-gateway"
$GatewayName="gateway"
$GatewayClassName="envoy"

$ClusterIssuerName="letsencrypt"
$CertManagerManagedIdentityName="cert-manager"
$CertManagerServiceAccountName="cert-manager"
$CertManagerNamespace="cert-manager"

$DnsZoneName="programmingwithwolfgang.com"
$DnsSubscriptionName="ProgrammingWithWolfgang"
$DnsSubscriptionId=$(az account show --subscription "$DnsSubscriptionName" --query id --output tsv)
$DnsResourceGroup="ProgrammingWithWolfgang"

$TraefikNamespace="traefik-ns"
$TraefikAppName="traefik"
$TraefikUrl="traefik.programmingwithwolfgang.com"
```

## Create AKS
```
az group create `
  --name $ResourceGroupName `
  --location $Location

az aks create `
  --name $AksName `
  --resource-group $ResourceGroupName `
    --enable-oidc-issuer `
    --enable-workload-identity

az aks get-credentials `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --overwrite-existing
```

## Deploy Envoy and create the Gateway and GatewayClass
```
helm install envoy oci://docker.io/envoyproxy/gateway-helm `
  --version v1.8.2 `
  --namespace $GatewayNamespace `
  --create-namespace

$GatewayClass = @"
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: $GatewayClassName
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
"@

$GatewayClass | kubectl apply -f -

$Gateway = @"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: $GatewayName
  namespace: $GatewayNamespace
spec:
  gatewayClassName: $GatewayClassName
  allowedListeners:
    namespaces:
      from: All
  listeners:
  - name: http-listener
    port: 80
    protocol: HTTP
"@

$Gateway | kubectl apply -f -

kubectl get gateway -n $GatewayNamespace 
```

might take a minute to switch Programmed = True

```
kubectl get gatewayclass

$Fqdn=$(kubectl get gateway $GatewayName -n $GatewayNamespace -o jsonpath='{.status.addresses[0].value}')
```

Update DNS

## Install the Cert Manager and ClusterIssuer
```
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

## Deploy Test App
```
kubectl create ns $TraefikNamespace

kubectl run $TraefikAppName `
  --image=traefik/whoami `
  --expose `
  --port=80 `
  --namespace=$TraefikNamespace

$ListenerSet = @"
apiVersion: gateway.networking.k8s.io/v1
kind: ListenerSet
metadata:
  name: "${TraefikAppName}-listener"
  namespace: $TraefikNamespace
  annotations:
    cert-manager.io/cluster-issuer: $ClusterIssuerName
spec:
  parentRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: $GatewayName
    namespace: $GatewayNamespace
  listeners:
    - name: https-domain
      protocol: HTTPS
      port: 443
      hostname: $TraefikUrl
      tls:
        mode: Terminate
        certificateRefs:
          - name: "${TraefikAppName}-tls-secret"
"@

$ListenerSet | kubectl apply -f -

kubectl get listenerset -n $TraefikNamespace

$HttpRouteTraefik = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: traefik-http-route
  namespace: $TraefikNamespace
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: ${TraefikAppName}-listener
  hostnames:
    - $TraefikUrl
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: $TraefikAppName
          port: 80
"@

$HttpRouteTraefik | kubectl apply -f -

kubectl get all -n $TraefikNamespace

kubectl get certificate -A

$TraefikUrl
```
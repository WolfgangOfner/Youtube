## Define Variables
```
$ResourceGroupName="argocdui-demo"
$Location="CanadaCentral"
$AksName="argocd-aks"

$GatewayNamespace="envoy-gateway"
$GatewayName="gateway"
$GatewayClassName="envoy"

$ClusterIssuerName="letsencrypt"
$CertManagerNamespace="cert-manager"

$ArgoCdNamespace="argocd"
$ArgoCdUiUrl="argocd.programmingwithwolfgang.com"
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

## Deploy Envoy and create the Gateway and GatewayClass
```
helm install envoy oci://docker.io/envoyproxy/gateway-helm `
  --version v1.7.1 `
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
  annotations:
    cert-manager.io/cluster-issuer: $ClusterIssuerName
spec:
  gatewayClassName: $GatewayClassName
  listeners:
  - name: http-listener
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
  - name: argocdui-https-listener
    port: 443
    protocol: HTTPS
    hostname: $ArgoCdUiUrl
    allowedRoutes:
      namespaces:
        from: All 
    tls:
      certificateRefs:
        - group: ""
          kind: Secret
          name: argocd-ui-tls
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
  --version v1.19.2 `
  --set config.enableGatewayAPI=true `
  --set crds.enabled=true

$ClusterIssuer = @"
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: $ClusterIssuerName
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory # production endpoint
    # server: https://acme-staging-v02.api.letsencrypt.org/directory # staging endpoint
    email: # your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-private-key
    solvers:
      - http01:
          gatewayHTTPRoute:
            parentRefs:
              - name: $GatewayName
                namespace: $GatewayNamespace
                kind: Gateway
"@

$ClusterIssuer | kubectl apply -f -

kubectl get ClusterIssuer -o yaml
```

## Deploy ArgoCD and create an HTTPRoute
```
helm repo add argo https://argoproj.github.io/argo-helm --force-update

helm install argo-cd argo/argo-cd `
    --version 9.4.15 `
    --namespace $ArgoCdNamespace `
    --create-namespace `
    --set configs.params."server\.insecure"=true

kubectl get service -n $ArgoCdNamespace

$HttpRouteArgoCd = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-http-route
  namespace: $ArgoCdNamespace
spec:
  parentRefs:
  - name: $GatewayName
    namespace: $GatewayNamespace    
  hostnames:
  - $ArgoCdUiUrl
  rules:
  - matches:
    backendRefs:
    - name: argo-cd-argocd-server
      port: 80 
"@

$HttpRouteArgoCd | kubectl apply -f -
```
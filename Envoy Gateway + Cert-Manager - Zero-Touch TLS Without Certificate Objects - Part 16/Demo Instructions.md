## Define Variables
```
$AksName="envoy-gateway-aks"
$Location="CanadaCentral"
$ResourceGroupName="envoy-gateway-rg"

$GatewayNamespace="envoy-gateway"
$GatewayName="gateway"
$GatewayClassName="envoy"

$ClusterIssuerName="letsencrypt"
$CertManagerNamespace="cert-manager"

$TraefikNamespace="traefik-ns"
$TraefikHttpRoute="traefik-http-route"
$TraefikAppName="traefik"
$TraefikSecretName="traefik-letsencrypt-secret"
$TraefikUrl="traefik.programmingwithwolfgang.com"
```

## Create AKS
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
  --version v1.6.1 `
  --namespace $GatewayNamespace `
  --create-namespace

kubectl get gateway -A
kubectl get gatewayclass

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
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
  - name: traefik-https-listener
    port: 443
    protocol: HTTPS
    hostname: $TraefikUrl
    allowedRoutes:
      namespaces:
        from: All 
    tls:
      certificateRefs:
        - group: ""
          kind: Secret
          name: $TraefikSecretName
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
    email: wolfgang@programmingwithwolfgang.com # your-email@example.com
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

kubectl get ClusterIssuer -A -o yaml
```

## Deploy Test App
```
$TraefikDeployment = @"
apiVersion: v1
kind: Namespace
metadata:
  name: $TraefikNamespace
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${TraefikAppName}-deployment"
  namespace: $TraefikNamespace
  labels:
    app: $TraefikAppName
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $TraefikAppName
  template:
    metadata:
      labels:
        app: $TraefikAppName
    spec:
      containers:
      - name: whoami
        image: traefik/whoami:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "64Mi"
---
apiVersion: v1
kind: Service
metadata:  
  name: $TraefikAppName
  namespace: $TraefikNamespace
  labels:
    app: $TraefikAppName
spec:
  type: ClusterIP
  selector:
    app: $TraefikAppName
  ports:
  - port: 80
    targetPort: 80 
    protocol: TCP
    name: http
"@

$TraefikDeployment | kubectl apply -f -

$HttpRouteTraefik = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: traefik-http-route
  namespace: $TraefikNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $GatewayNamespace
  hostnames:
    - "$TraefikUrl" 
  rules:
    - matches:
      backendRefs:
        - name: $TraefikAppName
          port: 80
"@

$HttpRouteTraefik | kubectl apply -f -

kubectl get all -n $TraefikNamespace

kubectl describe gateway -n $GatewayNamespace

curl https://$TraefikUrl -UseBasicParsing
```
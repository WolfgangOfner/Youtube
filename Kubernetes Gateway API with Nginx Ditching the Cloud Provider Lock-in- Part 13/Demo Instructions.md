## Define Variables
```
$AksName="nginx-gateway-aks"
$Location="CanadaCentral"
$ResourceGroupName="nginx-gateway-rg"

$GatewayNamespace="nginx-gateway"
$GatewayName="gateway"

$TraefikNamespace="traefik-ns"
$TraefikAppName="traefik"
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

## Deploy Gateway API CRDs, Nginx and create the Gateway
```
kubectl apply -k "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.4.1"

helm install nginx-gateway-fabric oci://ghcr.io/nginx/charts/nginx-gateway-fabric `
  --create-namespace `
  --namespace $GatewayNamespace

kubectl get gateway -A
kubectl get gatewayclass

$Gateway = @"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: $GatewayName
  namespace: $GatewayNamespace
spec:
  gatewayClassName: nginx
  listeners:
  - name: http-listener
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
"@

$Gateway | kubectl apply -f -

kubectl get gateway -n $GatewayNamespace

$Fqdn=$(kubectl get gateway $GatewayName -n $GatewayNamespace -o jsonpath='{.status.addresses[0].value}')
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

curl http://$Fqdn -UseBasicParsing
```
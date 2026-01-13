## Define Variables
```
$AksName="traefik-gateway-aks"
$Location="CanadaCentral"
$ResourceGroupName="traefik-gateway-rg"

$GatewayNamespace="traefik-gateway"
$GatewayName="traefik-gateway"
$GatewayClassName="traefik"

$TestAppNamespace="testapp-ns"
$TestAppName="testapp"
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

## Deploy Traefik and update Gateway
```
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm install traefik traefik/traefik `
  --set providers.kubernetesGateway.enabled=true `
  --namespace $GatewayNamespace `
  --create-namespace

kubectl get all -n $GatewayNamespace
kubectl get gateway -n $GatewayNamespace
kubectl describe gateway $GatewayName -n $GatewayNamespace

$Gateway = @"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: $GatewayName
  namespace: $GatewayNamespace
spec:
  gatewayClassName: $GatewayClassName
  listeners:
    - name: web
      protocol: HTTP
      port: 8000
      allowedRoutes:
        namespaces:
          from: All
"@

$Gateway | kubectl apply -f -

kubectl get gateway -n $GatewayNamespace
kubectl get gatewayclass

$Fqdn=$(kubectl get gateway $GatewayName -n $GatewayNamespace -o jsonpath='{.status.addresses[0].value}')
```

## Deploy Test Application
```
$DemoAppDeployment = @"
apiVersion: v1
kind: Namespace
metadata:
  name: $TestAppNamespace
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${TestAppName}-deployment"
  namespace: $TestAppNamespace
  labels:
    app: $TestAppName
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $TestAppName
  template:
    metadata:
      labels:
        app: $TestAppName
    spec:
      containers:
      - name: whoami
        image: traefik/whoami:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:  
  name: $TestAppName
  namespace: $TestAppNamespace
  labels:
    app: $TestAppName
spec:
  type: ClusterIP
  selector:
    app: $TestAppName
  ports:
  - port: 80
    targetPort: 80 
    protocol: TCP
    name: http
"@

$DemoAppDeployment | kubectl apply -f -

$HttpRoute = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: "${TestAppName}-http-route"
  namespace: $TestAppNamespace
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
        - name: $TestAppName
          port: 80
"@

$HttpRoute | kubectl apply -f -

kubectl get all -n $TestAppNamespace

curl http://$Fqdn -UseBasicParsing
```
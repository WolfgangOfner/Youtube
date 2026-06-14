## Define Variables
```
$AksName="gateway-api-aks"
$Location="CanadaCentral"
$ResourceGroupName="gateway-api-rg"

$GatewayNamespace="envoy-gateway"
$GatewayName="gateway"
$GatewayClassName="envoy"

$DemoNamespace="demo-ns"
$DemoAppNameOne="demoone"
$DemoAppNameTwo="demotwo"
$DemoUrl="demo.programmingwithwolfgang.com" # change to your URL
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
  --version v1.7.0 `
  --namespace $GatewayNamespace `
  --create-namespace `
  --set deployment.replicas=3

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
    hostname: $DemoUrl
    allowedRoutes:
      namespaces:
        from: All 
"@

$Gateway | kubectl apply -f -

kubectl get gateway -n $GatewayNamespace 
kubectl describe gateway $GatewayName -n $GatewayNamespace
```

might take a minute to switch Programmed = True

```
kubectl get gatewayclass

kubectl get gateway $GatewayName -n $GatewayNamespace -o jsonpath='{.status.addresses[0].value}'
```

Update DNS

## Deploy Test App
```
$DemoOneDeployment = @"
apiVersion: v1
kind: Namespace
metadata:
  name: $DemoNamespace
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${DemoAppNameOne}-deployment"
  namespace: $DemoNamespace
  labels:
    app: $DemoAppNameOne
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $DemoAppNameOne
  template:
    metadata:
      labels:
        app: $DemoAppNameOne
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
  name: $DemoAppNameOne
  namespace: $DemoNamespace
  labels:
    app: $DemoAppNameOne
spec:
  type: ClusterIP
  selector:
    app: $DemoAppNameOne
  ports:
  - port: 80
    targetPort: 80 
    protocol: TCP
    name: http
"@

$DemoOneDeployment | kubectl apply -f -

$DemoTwoDeployment = @"
apiVersion: v1
kind: Namespace
metadata:
  name: $DemoNamespace
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${DemoAppNameTwo}-deployment"
  namespace: $DemoNamespace
  labels:
    app: $DemoAppNameTwo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $DemoAppNameTwo
  template:
    metadata:
      labels:
        app: $DemoAppNameTwo
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
  name: $DemoAppNameTwo
  namespace: $DemoNamespace
  labels:
    app: $DemoAppNameTwo
spec:
  type: ClusterIP
  selector:
    app: $DemoAppNameTwo
  ports:
  - port: 80
    targetPort: 80 
    protocol: TCP
    name: http
"@

$DemoTwoDeployment | kubectl apply -f -

kubectl get all -n $DemoNamespace

$HttpRouteDemoApp = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: demo-http-route
  namespace: $DemoNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $GatewayNamespace
  hostnames:
    - "$DemoUrl" 
  rules:
    - matches:
      backendRefs:
        - name: $DemoAppNameOne
          port: 80
"@

$HttpRouteDemoApp | kubectl apply -f -

curl http://$DemoUrl -UseBasicParsing
```

## Path Routing
```
$HttpRouteDemoApp = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: demo-http-route
  namespace: $DemoNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $GatewayNamespace
  hostnames:
    - "$DemoUrl" 
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /routing 
        - path:
            type: Exact
            value: /exact 
      backendRefs:
        - name: $DemoAppNameOne
          port: 80
    - backendRefs:
      - name: $DemoAppNameTwo
        port: 80
"@

$HttpRouteDemoApp | kubectl apply -f -

curl http://$DemoUrl -UseBasicParsing
curl http://$DemoUrl/exact -UseBasicParsing
curl http://$DemoUrl/exact/abc -UseBasicParsing
curl http://$DemoUrl/routing/abc -UseBasicParsing
```

## Routing based on Weight
```
$HttpRouteDemoApp = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: demo-http-route
  namespace: $DemoNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $GatewayNamespace
  hostnames:
    - "$DemoUrl"
  rules: 
  - backendRefs:
    - name: $DemoAppNameOne
      port: 80
      weight: 20
    - name: $DemoAppNameTwo
      port: 80
      weight: 80
"@

$HttpRouteDemoApp | kubectl apply -f -

DemoUrl="demo.programmingwithwolfgang.com"
watch -n 1 curl http://$DemoUrl
```
## Define Variables
```
$InfrastructureNamespace="alb-infra"
$GatewayName="gateway"

$NginxNamespace="nginx-ns"
$NginxHttpRoute="nginx-http-route"
$NginxAppName="nginx"
$NginxUrl="nginx.programmingwithwolfgang.com"
```

## Create Nginx (Test App) Deployment
```
$Fqdn=$(kubectl get gateway $GatewayName -n $InfrastructureNamespace -o jsonpath='{.status.addresses[0].value}')
kubectl get gateway $GatewayName -n $InfrastructureNamespace -o yaml

kubectl create ns $NginxNamespace

$NginxDeployment = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${NginxAppName}-deployment"
  namespace: $NginxNamespace
  labels:
    app: $NginxAppName
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $NginxAppName
  template:
    metadata:
      labels:
        app: $NginxAppName
    spec:
      containers:
      - name: $NginxAppName
        image: nginx:latest
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
  name: $NginxAppName
  namespace: $NginxNamespace
  labels:
    app: $NginxAppName
spec:
  type: ClusterIP
  selector:
    app: $NginxAppName
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
"@

$NginxDeployment | kubectl apply -f -

kubectl get all -n $NginxNamespace
```

## Deploy HTTPRoutes and test Access
```
$HttpRouteNginx = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $NginxHttpRoute
  namespace: $NginxNamespace
spec:
  parentRefs:
  - name: $GatewayName
    namespace: $InfrastructureNamespace
  rules:
  - backendRefs:
    - name: $NginxAppName
      port: 80
"@

$HttpRouteNginx | kubectl apply -f -

kubectl get httproute $NginxHttpRoute -n $NginxNamespace -o yaml

$HttpRouteNginx = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $NginxHttpRoute
  namespace: $NginxNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $InfrastructureNamespace
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /nginx
      backendRefs:
        - name: nginx
          port: 80
"@

$HttpRouteNginx | kubectl apply -f -
```

## Deploy Traefik as second Demo App
```
$TraefikNamespace="traefik-ns"
$TraefikHttpRoute="traefik-http-route"
$TraefikAppName="traefik"
$TraefikUrl="traefik.programmingwithwolfgang.com"

kubectl create ns $TraefikNamespace

$TraefikDeployment = @"
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

kubectl get all -n $TraefikNamespace
```

## Deploy HTTPRoutes and test Access
```
$HttpRouteTraefik = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $TraefikHttpRoute
  namespace: $TraefikNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $InfrastructureNamespace
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /traefik 
      backendRefs:
        - name: $TraefikAppName
          port: 80
"@

$HttpRouteTraefik | kubectl apply -f -

$HttpRouteNginx = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $NginxHttpRoute
  namespace: $NginxNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $InfrastructureNamespace 
  hostnames:
    - "$NginxUrl" 
  rules:
    - matches:
      backendRefs:
        - name: $NginxAppName
          port: 80
"@

$HttpRouteNginx | kubectl apply -f -


$HttpRouteTraefik = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $TraefikHttpRoute
  namespace: $TraefikNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $InfrastructureNamespace
  hostnames:
    - "$TraefikUrl"
  rules:
    - matches:
      backendRefs:
        - name: $TraefikAppName
          port: 80
"@

$HttpRouteTraefik | kubectl apply -f -
```
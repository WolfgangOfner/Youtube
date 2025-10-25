## Define Variables
```
$InfrastructureNamespace="alb-infra"
$GatewayName="gateway"

$RoutingDemoNamespace="routing-ns"
$RoutingHttpRoute="routing-http-route"
$RoutingAppNameOne="routingone"
$RoutingAppNameTwo="routingtwo"
$RoutingAppNameThree="routingthree"
$RoutingAppNameFour="routingfour"

$Fqdn=$(kubectl get gateway $GatewayName -n $InfrastructureNamespace -o jsonpath='{.status.addresses[0].value}')
$RoutingUrl="routing.programmingwithwolfgang.com"
```

## Create 4 Demo Apps
```
kubectl get gateway $GatewayName -n $InfrastructureNamespace -o yaml
kubectl create ns $RoutingDemoNamespace

$RoutingDeployment = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${RoutingAppNameOne}-deployment"
  namespace: $RoutingDemoNamespace
  labels:
    app: $RoutingAppNameOne
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $RoutingAppNameOne
  template:
    metadata:
      labels:
        app: $RoutingAppNameOne
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
  name: $RoutingAppNameOne
  namespace: $RoutingDemoNamespace
  labels:
    app: $RoutingAppNameOne
spec:
  type: ClusterIP
  selector:
    app: $RoutingAppNameOne
  ports:
  - port: 80
    targetPort: 80 
    protocol: TCP
    name: http
"@

$RoutingDeployment | kubectl apply -f -

$RoutingDeployment = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${RoutingAppNameTwo}-deployment"
  namespace: $RoutingDemoNamespace
  labels:
    app: $RoutingAppNameTwo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $RoutingAppNameTwo
  template:
    metadata:
      labels:
        app: $RoutingAppNameTwo
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
  name: $RoutingAppNameTwo
  namespace: $RoutingDemoNamespace
  labels:
    app: $RoutingAppNameTwo
spec:
  type: ClusterIP
  selector:
    app: $RoutingAppNameTwo
  ports:
  - port: 80
    targetPort: 80 
    protocol: TCP
    name: http
"@

$RoutingDeployment | kubectl apply -f -

$RoutingDeployment = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${RoutingAppNameThree}-deployment"
  namespace: $RoutingDemoNamespace
  labels:
    app: $RoutingAppNameThree
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $RoutingAppNameThree
  template:
    metadata:
      labels:
        app: $RoutingAppNameThree
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
  name: $RoutingAppNameThree
  namespace: $RoutingDemoNamespace
  labels:
    app: $RoutingAppNameThree
spec:
  type: ClusterIP
  selector:
    app: $RoutingAppNameThree
  ports:
  - port: 80
    targetPort: 80 
    protocol: TCP
    name: http
"@

$RoutingDeployment | kubectl apply -f -

$RoutingDeployment = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${RoutingAppNameFour}-deployment"
  namespace: $RoutingDemoNamespace
  labels:
    app: $RoutingAppNameFour
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $RoutingAppNameFour
  template:
    metadata:
      labels:
        app: $RoutingAppNameFour
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
  name: $RoutingAppNameFour
  namespace: $RoutingDemoNamespace
  labels:
    app: $RoutingAppNameFour
spec:
  type: ClusterIP
  selector:
    app: $RoutingAppNameFour
  ports:
  - port: 80
    targetPort: 80 
    protocol: TCP
    name: http
"@

$RoutingDeployment | kubectl apply -f -

kubectl get all -n $RoutingDemoNamespace
```

## Path Routing
```
$HttpRouteRouting = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $RoutingHttpRoute
  namespace: $RoutingDemoNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $InfrastructureNamespace
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /routing 
        - path:
            type: Exact
            value: /exact 
      backendRefs:
        - name: $RoutingAppNameOne
          port: 80
"@

$HttpRouteRouting | kubectl apply -f -

curl $fqdn/routing

$HttpRouteRouting = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $RoutingHttpRoute
  namespace: $RoutingDemoNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $InfrastructureNamespace
  rules:
    - matches:
        - path:
            type: RegularExpression
            # 2. Define the regex pattern. This pattern means:
            #    ^/         -> Starts with a slash
            #    [^/]+      -> Followed by one or more characters that are NOT a slash (the wildcard segment, e.g., 'v1')
            #    /regex      -> Followed by the literal '/regex'
            # This effectively matches paths like /v1/regex, /admin/regex, /foo/regex, etc.
            value: ^/[^/]+/regex
      backendRefs:
        - name: $RoutingAppNameOne
          port: 80
"@

$HttpRouteRouting | kubectl apply -f -

curl $fqdn/routing/regex
```

## Header Routing
```
$HttpRouteRouting = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $RoutingHttpRoute
  namespace: $RoutingDemoNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $InfrastructureNamespace
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /routing 
      backendRefs:
        - name: $RoutingAppNameOne
          port: 80
    - matches:
        - headers:
          - type: Exact
            name: header
            value: routing 
          path:
            type: PathPrefix
            value: /routing
      backendRefs:
        - name: $RoutingAppNameTwo
          port: 80
"@

$HttpRouteRouting | kubectl apply -f -

curl $fqdn/routing -H "header: routing"
curl $fqdn/routing
curl $fqdn/routing -H "header: abc"
```

## Query String Routing
```
$HttpRouteRouting = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $RoutingHttpRoute
  namespace: $RoutingDemoNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $InfrastructureNamespace
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /routing 
      backendRefs:
        - name: $RoutingAppNameOne
          port: 80
    - matches:
        - headers:
          - type: Exact
            name: header
            value: routing 
          path:
            type: PathPrefix
            value: /routing
      backendRefs:
        - name: $RoutingAppNameTwo
          port: 80
    - matches:
        - queryParams:
          - type: Exact
            name: query
            value: routing 
          path:
            type: PathPrefix
            value: /routing
      backendRefs:
        - name: $RoutingAppNameThree
          port: 80
"@

$HttpRouteRouting | kubectl apply -f -

curl $fqdn/routing?query=routing
```

## Hostname Routing
```
$HttpRouteRouting = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $RoutingHttpRoute
  namespace: $RoutingDemoNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $InfrastructureNamespace
  hostnames:
    - "$RoutingUrl" 
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /routing 
      backendRefs:
        - name: $RoutingAppNameOne
          port: 80
    - matches:
        - headers:
          - type: Exact
            name: header
            value: routing 
          path:
            type: PathPrefix
            value: /routing
      backendRefs:
        - name: $RoutingAppNameTwo
          port: 80
    - matches:
        - queryParams:
          - type: Exact
            name: query
            value: routing 
          path:
            type: PathPrefix
            value: /routing
      backendRefs:
        - name: $RoutingAppNameThree
          port: 80
"@

$HttpRouteRouting | kubectl apply -f -

curl http://$RoutingUrl/routing

```

## Default Routing
```
$HttpRouteRouting = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $RoutingHttpRoute
  namespace: $RoutingDemoNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $InfrastructureNamespace
  hostnames:
    - "$RoutingUrl" 
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /routing 
      backendRefs:
        - name: $RoutingAppNameOne
          port: 80
    - matches:
        - headers:
          - type: Exact
            name: header
            value: routing
          path:
            type: PathPrefix
            value: /routing
      backendRefs:
        - name: $RoutingAppNameTwo
          port: 80
    - matches:
        - queryParams:
          - type: Exact
            name: query
            value: routing 
          path:
            type: PathPrefix
            value: /routing
      backendRefs:
        - name: $RoutingAppNameThree
          port: 80
    - backendRefs:
      - name: $RoutingAppNameFour
        port: 80
"@

$HttpRouteRouting | kubectl apply -f -

curl http://$RoutingUrl/routing

curl http://$RoutingUrl/routing?query=routing

curl http://$RoutingUrl
```
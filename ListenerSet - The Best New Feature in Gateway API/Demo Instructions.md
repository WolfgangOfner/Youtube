## Define Variables
```
$AksName="listenerset-aks"
$Location="CanadaCentral"
$ResourceGroupName="listenerset-rg"

$GatewayNamespace="envoy-gateway"
$GatewayName="gateway"
$GatewayClassName="envoy"

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
spec:
  parentRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: $GatewayName
    namespace: $GatewayNamespace
  listeners:
    - name: http-traefik
      protocol: HTTP
      port: 80
      hostname: $TraefikUrl
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

$TraefikUrl
```
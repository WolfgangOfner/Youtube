## Define Variables
```powershell
$AksMcpHelmDeploymentName="aks-mcp"
$AksMcpNamespace="aks-mcp"
$AksMcpUrl="aks-mcp.programmingwithwolfgang.com"

$GatewayNamespace="envoy-gateway"
$GatewayName="gateway"
$GatewayClassName="envoy"
```

## Configure the Gateway API
```powershell
kubectl port-forward svc/$AksMcpHelmDeploymentName 8000:8000 -n $AksMcpNamespace

kubectl get gateway -n $GatewayNamespace

kubectl get all -n $AksMcpNamespace

$ListenerSet = @"
apiVersion: gateway.networking.k8s.io/v1
kind: ListenerSet
metadata:
  name: aks-mcp-listener
  namespace: $AksMcpNamespace
spec:
  parentRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: $GatewayName
    namespace: $GatewayNamespace
  listeners:
  - name: http-mcp
    hostname: $AksMcpUrl
    port: 80
    protocol: HTTP
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

cd aks-mcp/chart

helm upgrade $AksMcpHelmDeploymentName . `
  --namespace $AksMcpNamespace `
  --reuse-values `
  --set "security.allowedHosts={$AksMcpUrl}"
  ```
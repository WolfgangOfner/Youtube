## Define Variables
```
$InfrastructureNamespace="alb-infra"
$GatewayName="gateway"

$RoutingDemoNamespace="routing-ns"
$RoutingHttpRoute="routing-http-route"
$RoutingAppNameOne="routingone"
$RoutingAppNameTwo="routingtwo"

$RoutingUrl="routing.programmingwithwolfgang.com"
```

## URL Rewrite
```
kubectl get all -n $RoutingDemoNamespace

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
            value: /my
      filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /replaced
      backendRefs:
        - name: $RoutingAppNameOne
          port: 80
    - backendRefs:
      - name: $RoutingAppNameTwo
        port: 80
"@

$HttpRouteRouting | kubectl apply -f -

curl http://$RoutingUrl/my/path
curl http://$RoutingUrl/path

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
            value: /my/path
      filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplaceFullPath
              replaceFullPath: /replaced
      backendRefs:
        - name: $RoutingAppNameOne
          port: 80
    - backendRefs:
      - name: $RoutingAppNameTwo
        port: 80
"@

$HttpRouteRouting | kubectl apply -f -

curl http://$RoutingUrl/my/path
curl http://$RoutingUrl/my/path/abc
curl http://$RoutingUrl/my
```

## URL Redirect
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
        value: /my/path
    filters:
      - type: RequestRedirect
        requestRedirect:
          path:
            type: ReplaceFullPath
            replaceFullPath: /replaced
          statusCode: 302
  - backendRefs:
    - name: $RoutingAppNameOne
      port: 80
"@

$HttpRouteRouting | kubectl apply -f -

curl http://$RoutingUrl/my/path -v
curl http://$RoutingUrl/my/path/abc -v
curl http://$RoutingUrl/my -v

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
        value: /my/path
    filters:
      - type: RequestRedirect
        requestRedirect:
          path:
            type: ReplacePrefixMatch
            replacePrefixMatch: /replaced
          statusCode: 302
  - backendRefs:
    - name: $RoutingAppNameOne
      port: 80
"@

$HttpRouteRouting | kubectl apply -f -

curl http://$RoutingUrl/my/path -v
curl http://$RoutingUrl/my/path/abc -v
curl http://$RoutingUrl/my -v
```
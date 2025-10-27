## Define Variables
```
$InfrastructureNamespace="alb-infra"
$GatewayName="gateway"

$RoutingDemoNamespace="routing-ns"
$RoutingHttpRoute="routing-http-route"
$RoutingAppNameThree="routingthree"
$RoutingAppNameFour="routingfour"
$RoutingUrl="routing.programmingwithwolfgang.com"
```

## Routing based on Weight
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
  - backendRefs:
    - name: $RoutingAppNameThree
      port: 80
      weight: 50
    - name: $RoutingAppNameFour
      port: 80
      weight: 50
"@

$HttpRouteRouting | kubectl apply -f -

watch -n 1 curl http://$RoutingUrl

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
  - backendRefs:
    - name: $RoutingAppNameThree
      port: 80
      weight: 20
    - name: $RoutingAppNameFour
      port: 80
      weight: 80
"@

$HttpRouteRouting | kubectl apply -f -

watch -n 1 curl http://$RoutingUrl
```

Weight must be an integer and is relative, meaning weight of 1 and 1 is the same as weight of 1000 and 1000. Also 20 and 80 is the same ratio as 400 and 1600. 
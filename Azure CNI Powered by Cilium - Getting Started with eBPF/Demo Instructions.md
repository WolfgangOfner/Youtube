## Define Variables
```
$AksName="cilium-aks"
$Location="CanadaCentral"
$ResourceGroupName="cilium-rg"

$FrontendNamespace="frontend"
$BackendNamespace="backend"
```

## Create AKS
```
az group create `
  --name $ResourceGroupName `
  --location $Location

az aks create `
  --name $AksName `
  --resource-group $ResourceGroupName `
  --network-plugin azure `
  --network-dataplane cilium

az aks get-credentials `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --overwrite-existing
```

## Setup Pods
```
kubectl create ns $BackendNamespace
kubectl create ns $FrontendNamespace

# Target backend (system namespace)
kubectl run backend --image=nginx `
  --labels="app=backend,team=platform" `
  -n $BackendNamespace `
  --expose --port=80

# Authorized frontend (tenant namespace)
kubectl run frontend --image=curlimages/curl `
  --labels="app=frontend,tenant=alpha" `
  -n $FrontendNamespace `
  --command -- sleep 3600

# Unauthorized evil pod (same tenant namespace)
kubectl run evil --image=curlimages/curl `
  --labels="app=evil,tenant=alpha" `
  -n $FrontendNamespace `
  --command -- sleep 3600

# Wait for everything to be Ready
kubectl wait --for=condition=Ready pod/backend -n $BackendNamespace --timeout=60s
kubectl wait --for=condition=Ready pod/frontend -n $FrontendNamespace --timeout=60s
kubectl wait --for=condition=Ready pod/evil -n $FrontendNamespace --timeout=60s
```

## Demo 1: Identity-Based Microsegmentation
```
kubectl exec -n $FrontendNamespace frontend -- curl -sS --connect-timeout 3 -o /dev/null -w "frontend: %{http_code}`n" http://backend.$BackendNamespace.svc.cluster.local
kubectl exec -n $FrontendNamespace evil -- curl -sS --connect-timeout 3 -o /dev/null -w "evil: %{http_code}`n" http://backend.$BackendNamespace.svc.cluster.local

$CiliumNetworkPolicy = @"
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: backend-allow-frontend-only
  namespace: $BackendNamespace
spec:
  endpointSelector:
    matchLabels:
      app: backend
      team: platform
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
        tenant: alpha
        k8s:io.kubernetes.pod.namespace: $FrontendNamespace
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
"@

$CiliumNetworkPolicy | kubectl apply -f -

kubectl exec -n $FrontendNamespace frontend -- curl -sS --connect-timeout 3 -o /dev/null -w "frontend: %{http_code}`n" http://backend.$BackendNamespace.svc.cluster.local

# DROPPED — evil's identity does not match (will hang then timeout)
kubectl exec -n $FrontendNamespace evil -- curl -sS --connect-timeout 3 -o /dev/null -w "evil:    %{http_code}`n" http://backend.$BackendNamespace.svc.cluster.local

kubectl get cep frontend -n $FrontendNamespace

kubectl delete pod frontend -n $FrontendNamespace

kubectl run frontend --image=curlimages/curl `
  --labels="app=frontend,tenant=alpha" `
  -n $FrontendNamespace `
  --command -- sleep 3600

kubectl wait --for=condition=Ready pod/frontend -n $FrontendNamespace --timeout=60s

kubectl get cep frontend -n $FrontendNamespace

kubectl exec -n $FrontendNamespace frontend -- curl -sS --connect-timeout 3 -o /dev/null -w "frontend (new IP): %{http_code}`n" http://backend.$BackendNamespace.svc.cluster.local
```

## Demo 2: Strict Egress Control via CIDR
```
$CiliumNetworkPolicy = @"
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: restrict-egress
  namespace: $FrontendNamespace
spec:
  endpointSelector:
    matchLabels:
      app: frontend
  egress:
  - toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: ANY
  - toEntities:
    - host
    - remote-node
  - toCIDR:
    - "140.82.112.0/20"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
"@

$CiliumNetworkPolicy | kubectl apply -f -

# ALLOWED — GitHub's CIDR
kubectl exec -n $FrontendNamespace frontend -- curl -sS --connect-timeout 5 -o /dev/null -w "github.com -> %{http_code}`n" https://github.com

# DROPPED — Cloudflare DNS, not in any allow rule
kubectl exec -n $FrontendNamespace frontend -- curl -sS --connect-timeout 5 -o /dev/null -w "1.1.1.1 -> %{http_code}`n" https://1.1.1.1

# DROPPED — outside the allowed CIDR
kubectl exec -n $FrontendNamespace frontend -- curl -sS --connect-timeout 5 -o /dev/null -w "example.com -> %{http_code}`n" https://example.com

kubectl exec -n $FrontendNamespace evil -- curl -sS --connect-timeout 3 -o /dev/null -w "evil -> 1.1.1.1: %{http_code}`n" https://1.1.1.1

kubectl exec -n $FrontendNamespace frontend -- curl -sS --connect-timeout 3 -o /dev/null -w "frontend: %{http_code}`n" http://backend.$BackendNamespace.svc.cluster.local

kubectl exec -n $FrontendNamespace evil -- curl -sS --connect-timeout 3 -o /dev/null -w "evil: %{http_code}`n" http://backend.$BackendNamespace.svc.cluster.local
```

## Demo 3: Inspecting the eBPF Data Plane
```
$BackendNamespaceNodeName  = kubectl get pod backend -n $BackendNamespace -o jsonpath='{.spec.nodeName}'
$FrontendNamespaceNodeName  = kubectl get pod frontend -n $FrontendNamespace -o jsonpath='{.spec.nodeName}'
$CiliumBackendPod = kubectl get pods -n kube-system -l k8s-app=cilium --field-selector "spec.nodeName=$BackendNamespaceNodeName" -o jsonpath='{.items[0].metadata.name}'

Write-Host "Backend node: $BackendNamespaceNodeName"
Write-Host "Cilium agent: $CiliumBackendPod"

kubectl get cep -A

$BackendEndpointId = kubectl get cep backend -n $BackendNamespace -o jsonpath='{.status.id}'

kubectl exec -n kube-system $CiliumBackendPod -c cilium-agent -- cilium bpf policy get $BackendEndpointId

kubectl exec -it -n kube-system $CiliumBackendPod -c cilium-agent -- cilium monitor -t drop

kubectl exec -n frontend evil -- curl -sS --connect-timeout 3 http://backend.$BackendNamespace.svc.cluster.local
```

## Demo 4: Cluster-Wide Tenant Isolation
```
$CiliumClusterwideNetworkPolicy = @"
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: tenant-isolation
spec:
  description: "Any tenant-labeled pod may only receive traffic from sources that also carry a tenant label (cluster-wide invariant)"
  endpointSelector:
    matchExpressions:
    - { key: tenant, operator: Exists }
  ingress:
  - fromRequires:
    - matchExpressions:
      - { key: tenant, operator: Exists }
"@

$CiliumClusterwideNetworkPolicy | kubectl apply -f -

kubectl get ciliumclusterwidenetworkpolicy

kubectl run tenant-app --image=nginx `
  --labels="app=tenant-app,tenant=alpha" `
  -n $FrontendNamespace `
  --expose --port=80

kubectl wait --for=condition=Ready pod/tenant-app -n $FrontendNamespace --timeout=60s

$CiliumNetworkPolicy = @"
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: tenant-app-allow-all
  namespace: $FrontendNamespace
spec:
  endpointSelector:
    matchLabels:
      app: tenant-app
  ingress:
  - fromEndpoints:
    - matchExpressions:
      - { key: "k8s:io.kubernetes.pod.namespace", operator: Exists }
"@

$CiliumNetworkPolicy | kubectl apply -f -

kubectl run no-tenant-pod --image=curlimages/curl `
  --labels="app=no-tenant" `
  -n $BackendNamespace `
  --command -- sleep 3600

kubectl wait --for=condition=Ready pod/no-tenant-pod -n $BackendNamespace --timeout=60s

kubectl exec -n $FrontendNamespace evil -- curl -sS --connect-timeout 3 -o /dev/null `
  -w "evil (tenant=alpha) -> tenant-app: %{http_code}`n" `
  http://tenant-app.$FrontendNamespace.svc.cluster.local

# DROPPED — no-tenant-pod has no tenant label
kubectl exec -n $BackendNamespace no-tenant-pod -- curl -sS --connect-timeout 3 -o /dev/null `
  -w "no-tenant-pod (no label) -> tenant-app: %{http_code}`n" `
  http://tenant-app.$FrontendNamespace.svc.cluster.local

kubectl delete ciliumclusterwidenetworkpolicy tenant-isolation

kubectl exec -n $FrontendNamespace evil -- curl -sS --connect-timeout 3 -o /dev/null -w "evil -> tenant-app: %{http_code}`n" http://tenant-app.$FrontendNamespace.svc.cluster.local

kubectl exec -n $BackendNamespace no-tenant-pod -- curl -sS --connect-timeout 3 -o /dev/null -w "no-tenant-pod -> tenant-app: %{http_code}`n" http://tenant-app.$FrontendNamespace.svc.cluster.local
```
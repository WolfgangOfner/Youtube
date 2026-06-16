## Define Variables
```
$AksName="acns-aks"
$AksNameMtls="acns-mtls-aks"
$Location="CanadaCentral"
$ResourceGroupName="acns-rg"

$FrontendNamespace="frontend"
$BackendNamespace="backend"
```

## Create AKS
```
az extension add --name aks-preview --upgrade
az feature register --namespace "Microsoft.ContainerService" --name "AdvancedNetworkingmTLSPreview"
az provider register --namespace Microsoft.ContainerService
az provider show --namespace Microsoft.ContainerService --query "registrationState" --output tsv

az group create `
  --name $ResourceGroupName `
  --location $Location

az aks create `
  --name $AksNameMtls `
  --resource-group $ResourceGroupName `
  --os-sku AzureLinux `
  --network-plugin azure `
  --network-plugin-mode overlay `
  --network-dataplane cilium `
  --enable-acns `
  --acns-advanced-networkpolicies None `
  --acns-transit-encryption-type mTLS `
  --no-wait

az aks create `
  --name $AksName `
  --resource-group $ResourceGroupName `
  --os-sku AzureLinux `
  --network-plugin azure `
  --network-plugin-mode overlay `
  --network-dataplane cilium `
  --enable-acns `
  --acns-advanced-networkpolicies L7 `
  --acns-datapath-acceleration-mode BpfVeth `
  --enable-azure-monitor-metrics

az aks get-credentials `
  --name $AksName `
  --resource-group $ResourceGroupName `
  --overwrite-existing
```

## Setup Pods
```
kubectl apply -f .\prometheus-configmap.yaml

kubectl create ns $BackendNamespace
kubectl create ns $FrontendNamespace

kubectl run frontend --image=curlimages/curl `
  --labels="app=frontend" `
  -n $FrontendNamespace `
  --command -- sleep 3600

kubectl wait --for=condition=Ready pod/frontend -n $FrontendNamespace --timeout=60s

kubectl get pods -n kube-system -l k8s-app=hubble-relay 
```

## Demo 1: Filter Egress by Domain Name (FQDN)
```
$FqdnPolicy = @"
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-github-by-name
  namespace: $FrontendNamespace
spec:
  endpointSelector:
    matchLabels:
      app: frontend
  egress:
  # Allow DNS so Cilium can learn IPs behind the domain
  - toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: kube-system
        k8s:k8s-app: kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: ANY
      rules:
        dns:
        - matchName: "github.com"
        - matchPattern: "*.github.com"
        # Alpine/musl search-domain workaround (documented ACNS limitation)
        - matchPattern: "github.com.*.*"
        - matchPattern: "github.com.*.*.*"
        - matchPattern: "github.com.*.*.*.*"
        - matchPattern: "github.com.*.*.*.*.*"
  - toFQDNs:
    - matchName: "github.com"
    - matchPattern: "*.github.com"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
"@

$FqdnPolicy | kubectl apply -f -

kubectl exec -n $FrontendNamespace frontend -- curl -sS --connect-timeout 5 -o /dev/null -w "github.com  -> %{http_code}`n" https://github.com

kubectl exec -n $FrontendNamespace frontend -- curl -sS --connect-timeout 5 -o /dev/null -w "example.com -> %{http_code}`n" https://example.com
```

## Demo 2: Filter by HTTP Method and Path (Layer 7)
```
kubectl delete CiliumNetworkPolicy allow-github-by-name -n frontend

kubectl run web --image=nginx `
  --labels="app=web" `
  -n $BackendNamespace `
  --expose --port=80

kubectl wait --for=condition=Ready pod/web -n $BackendNamespace --timeout=60s

kubectl exec -n $FrontendNamespace frontend -- curl -sS -o /dev/null -w "GET / -> %{http_code}`n" http://web.$BackendNamespace
kubectl exec -n $FrontendNamespace frontend -- curl -sS -o /dev/null -w "GET /admin -> %{http_code}`n" http://web.$BackendNamespace/admin

$L7Policy = @"
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-get-root-only
  namespace: $BackendNamespace
spec:
  endpointSelector:
    matchLabels:
      app: web
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
        k8s:io.kubernetes.pod.namespace: $FrontendNamespace
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      rules:
        http:
        - method: "GET"
          path: "/"
"@

$L7Policy | kubectl apply -f -

kubectl exec -n $FrontendNamespace frontend -- curl -sS -o /dev/null -w "GET / -> %{http_code}`n" http://web.$BackendNamespace

kubectl exec -n $FrontendNamespace frontend -- curl -sS -o /dev/null -w "GET /admin -> %{http_code}`n" http://web.$BackendNamespace/admin

kubectl exec -n $FrontendNamespace frontend -- curl -sS -o /dev/null -w "POST / -> %{http_code}`n" -X POST http://web.$BackendNamespace
```

## Demo 3: Speed Up Pod-to-Pod Traffic with eBPF Host Routing

New terminal

```
$AksName="no-acns-aks"
$Location="CanadaCentral"
$ResourceGroupName="acns-rg"

az aks create `
  --name $AksName `
  --resource-group $ResourceGroupName `
  --network-plugin azure `
  --network-plugin-mode overlay
  
az aks get-credentials `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --overwrite-existing
```

### Set up iperf3
```
kubectl run iperf-server --image=networkstatic/iperf3 `
  --labels="app=iperf-server" `
  --expose --port=5201 `
  -- -s

$IperfClient = @"
apiVersion: v1
kind: Pod
metadata:
  name: iperf-client
  labels:
    app: iperf-client
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: iperf-server
        topologyKey: kubernetes.io/hostname
  containers:
  - name: iperf-client
    image: networkstatic/iperf3
    command: ["sleep", "3600"]
"@

$IperfClient | kubectl apply -f -

kubectl wait --for=condition=Ready pod/iperf-server --timeout=60s
kubectl wait --for=condition=Ready pod/iperf-client --timeout=60s

kubectl get pods -o wide

kubectl exec iperf-client -- iperf3 -c iperf-server -l 12800 -t 10
```

## Demo 4: Pre-Built Grafana Dashboards
ACNS exports Hubble flow data as Prometheus metrics, but the dashboards
only light up once the metrics pipeline is in place. You need:

1. **Azure Monitor managed Prometheus** enabled on the cluster
   (creates the `ama-metrics-*` scrapers in `kube-system`).
2. **Azure Managed Grafana** linked to that Azure Monitor workspace
   (this is what makes the *Azure Monitor / Networking* dashboard
   folder appear in Grafana).
3. *(Optional)* Add `hubble_flows_processed_total` to the Hubble
   metrics keep-list in `ama-metrics-settings-configmap` if you want
   the **Pod Flows** dashboard to populate.

Verify the pipeline:

```
kubectl get pods -o wide -n kube-system | grep ama-
```

Then open Grafana → *Dashboards* → *Azure Managed Prometheus* →
*Kubernetes / Networking* and you should see Cilium, Hubble, DNS,
and Pod Flows dashboards.

## Demo 5: Encrypt Pod-to-Pod Traffic with mTLS 
```
az aks get-credentials `
  --name $AksNameMtls `
  --resource-group $ResourceGroupName `
  --overwrite-existing

kubectl create ns $BackendNamespace
kubectl create ns $FrontendNamespace

kubectl run frontend --image=curlimages/curl `
  --labels="app=frontend" `
  -n $FrontendNamespace `
  --command -- sleep 3600

kubectl run web --image=nginx `
  --labels="app=web" `
  -n $BackendNamespace `
  --expose --port=80

kubectl wait --for=condition=Ready pod/frontend -n $FrontendNamespace --timeout=60s
kubectl wait --for=condition=Ready pod/web -n $BackendNamespace --timeout=60s

kubectl rollout status -n kube-system daemonset/ztunnel-cilium --timeout=5m

kubectl get pods -n kube-system -l app.kubernetes.io/name=ztunnel-cilium 

kubectl label namespace $FrontendNamespace io.cilium/mtls-enabled=true
kubectl label namespace $BackendNamespace  io.cilium/mtls-enabled=true

kubectl get namespaces -l io.cilium/mtls-enabled=true

kubectl exec -n $FrontendNamespace frontend -- curl -sS http://web.$BackendNamespace.svc.cluster.local

kubectl exec -n kube-system spire-server-0 -c spire-server -- /opt/spire/bin/spire-server entry show
  
kubectl -n kube-system describe cm cilium-config | Select-String "enable-ztunnel" -Context 0,2
```
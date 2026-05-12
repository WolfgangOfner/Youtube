## Define Variables
```
$AksName="nap-aks"
$AksDefaultNapName="nap-with-default-aks"
$Location="CanadaCentral"
$ResourceGroupName="nap-rg"
```

## Create AKS
```
az group create `
  --name $ResourceGroupName `
  --location $Location

az aks create `
  --name $AksDefaultNapName `
  --resource-group $ResourceGroupName `
  --network-plugin azure `
  --network-plugin-mode overlay `
  --network-dataplane cilium `
  --node-vm-size Standard_B2s `
  --nodepool-name system `
  --node-count 1 `
  --node-provisioning-mode Auto `
  --no-wait

az aks create `
  --name $AksName `
  --resource-group $ResourceGroupName `
  --network-plugin azure `
  --network-plugin-mode overlay `
  --network-dataplane cilium `
  --node-vm-size Standard_B2s `
  --nodepool-name system `
  --node-count 1 `
  --node-provisioning-mode Auto `
  --node-provisioning-default-pools None

az aks get-credentials `
  --resource-group $ResourceGroupName `
  --name $AksDefaultNapName `
  --overwrite-existing
```

## Check default Nodepools and AKSNodeClass
```
kubectl get nodepools

kubectl describe nodepool default
kubectl describe nodepool system-surge

kubectl get AKSNodeClass
kubectl describe AKSNodeClass default
```

## Setup scaling with NAP
```
az aks get-credentials `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --overwrite-existing

kubectl get nodepools

$AksNodeClass = @"
apiVersion: karpenter.azure.com/v1beta1
kind: AKSNodeClass
metadata:
  name: my-node-class
spec:
  osDiskSizeGB: 128
"@

$AksNodeClass | kubectl apply -f -

$NodePool = @"
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: my-node-pool
spec:
  disruption:
    budgets:
      - nodes: 30%
    consolidateAfter: 0s
    consolidationPolicy: WhenEmptyOrUnderutilized
  template:
    metadata:
      labels:
        kubernetes.azure.com/ebpf-dataplane: cilium
    spec:
      expireAfter: 720h
      nodeClassRef:
        group: karpenter.azure.com
        kind: AKSNodeClass
        name: my-node-class
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values:
            - amd64
        - key: kubernetes.io/os
          operator: In
          values:
            - linux
        - key: karpenter.sh/capacity-type
          operator: In
          values:
            - on-demand
        - key: karpenter.azure.com/sku-family
          operator: In
          values:
            - D
      startupTaints:
        - effect: NoExecute
          key: node.cilium.io/agent-not-ready
          value: 'true'
"@

$NodePool | kubectl apply -f -

kubectl get nodes

$DemoApp = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nap-test-workload
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nap-test
  template:
    metadata:
      labels:
        app: nap-test
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          requests:
            cpu: "1"
            memory: "256Mi"
"@

$DemoApp | kubectl apply -f -

kubectl get pods -w
kubectl get nodes -L karpenter.azure.com/sku-name

kubectl scale deployment nap-test-workload --replicas=15
kubectl get pods -w

kubectl get nodes -L karpenter.azure.com/sku-name

kubectl scale deployment nap-test-workload --replicas=0
```

## Use specific SKUs
```
$NodePool = @"
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: my-node-pool
spec:
  disruption:
    budgets:
      - nodes: 30%
    consolidateAfter: 0s
    consolidationPolicy: WhenEmptyOrUnderutilized
  template:
    metadata:
      labels:
        kubernetes.azure.com/ebpf-dataplane: cilium
    spec:
      expireAfter: 720h
      nodeClassRef:
        group: karpenter.azure.com
        kind: AKSNodeClass
        name: my-node-class
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values:
            - amd64
        - key: kubernetes.io/os
          operator: In
          values:
            - linux
        - key: karpenter.sh/capacity-type
          operator: In
          values:
            - on-demand
        - key: karpenter.azure.com/sku-name
          operator: In
          values:
            - Standard_D8als_v6
            - Standard_E2ads_v6
      startupTaints:
        - effect: NoExecute
          key: node.cilium.io/agent-not-ready
          value: 'true'
"@

$NodePool | kubectl apply -f -

kubectl scale deployment nap-test-workload --replicas=15
kubectl get pods -w

kubectl get nodes -L karpenter.azure.com/sku-name

kubectl get nodes -L topology.disk.csi.azure.com/zone
kubectl scale deployment nap-test-workload --replicas=0
```

## Configure Availability Zones
```
$NodePool = @"
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: my-node-pool
spec:
  disruption:
    budgets:
      - nodes: 30%
    consolidateAfter: 0s
    consolidationPolicy: WhenEmptyOrUnderutilized
  template:
    metadata:
      labels:
        kubernetes.azure.com/ebpf-dataplane: cilium
    spec:
      expireAfter: 720h
      nodeClassRef:
        group: karpenter.azure.com
        kind: AKSNodeClass
        name: my-node-class
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values:
            - amd64
        - key: kubernetes.io/os
          operator: In
          values:
            - linux
        - key: karpenter.sh/capacity-type
          operator: In
          values:
            - on-demand
        - key: karpenter.azure.com/sku-name
          operator: In
          values:
            - Standard_D8als_v6
            - Standard_E2ads_v6
        - key: topology.kubernetes.io/zone
          operator: In
          values:
            - canadacentral-1
            - canadacentral-2
            - canadacentral-3
      startupTaints:
        - effect: NoExecute
          key: node.cilium.io/agent-not-ready
          value: 'true'
"@

$NodePool | kubectl apply -f -

kubectl scale deployment nap-test-workload --replicas=15
kubectl get pods -w

kubectl get nodes -L topology.disk.csi.azure.com/zone

kubectl scale deployment nap-test-workload --replicas=0

$DemoApp = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nap-test-workload
spec:
  replicas: 10
  selector:
    matchLabels:
      app: nap-test
  template:
    metadata:
      labels:
        app: nap-test
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          requests:
            cpu: "1"
            memory: "256Mi"
      topologySpreadConstraints:
        - maxSkew: 1
          minDomains: 3
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule # ScheduleAnyway
          labelSelector:
            matchLabels:
              app: nap-test
"@

$DemoApp | kubectl apply -f -

kubectl get nodes -L topology.disk.csi.azure.com/zone

kubectl scale deployment nap-test-workload --replicas=0

$DemoApp = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nap-test-workload
spec:
  replicas: 10
  selector:
    matchLabels:
      app: nap-test
  template:
    metadata:
      labels:
        app: nap-test
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          requests:
            cpu: "1"
            memory: "256Mi"
      topologySpreadConstraints:
        - maxSkew: 1
          minDomains: 3
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule # ScheduleAnyway
          labelSelector:
            matchLabels:
              app: nap-test
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: topology.kubernetes.io/zone
                operator: In
                values:
                - canadacentral-1
                - canadacentral-2
                - canadacentral-3
"@

$DemoApp | kubectl apply -f -

$DemoApp = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nap-test-workload
spec:
  replicas: 0
  selector:
    matchLabels:
      app: nap-test
  template:
    metadata:
      labels:
        app: nap-test
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          requests:
            cpu: "1"
            memory: "256Mi"
"@

$DemoApp | kubectl apply -f -
```

## Use On-demand and Spot VMs
```
$NodePool = @"
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: my-node-pool
spec:
  disruption:
    budgets:
      - nodes: 30%
    consolidateAfter: 0s
    consolidationPolicy: WhenEmptyOrUnderutilized
  template:
    metadata:
      labels:
        kubernetes.azure.com/ebpf-dataplane: cilium
    spec:
      expireAfter: 720h
      nodeClassRef:
        group: karpenter.azure.com
        kind: AKSNodeClass
        name: my-node-class
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values:
            - amd64
        - key: kubernetes.io/os
          operator: In
          values:
            - linux
        - key: karpenter.sh/capacity-type
          operator: In
          values:
            - on-demand
            - spot
        - key: karpenter.azure.com/sku-family
          operator: In
          values:
            - D # used because otherwise karpenter tries every sku-family
        - key: topology.kubernetes.io/zone
          operator: In
          values:
            - canadacentral-1
            - canadacentral-2
            - canadacentral-3
      startupTaints:
        - effect: NoExecute
          key: node.cilium.io/agent-not-ready
          value: 'true'
"@

$NodePool | kubectl apply -f -

kubectl scale deployment nap-test-workload --replicas=30

kubectl get nodes -L karpenter.sh/capacity-type

kubectl get events -A --field-selector type=Warning,reportingComponent=karpenter --sort-by='.lastTimestamp'

kubectl scale deployment nap-test-workload --replicas=0
```

## Use Multiple Node Pools
```
$NodePool = @"
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: my-node-pool
spec:
  disruption:
    budgets:
      - nodes: 30%
    consolidateAfter: 0s
    consolidationPolicy: WhenEmptyOrUnderutilized
  template:
    metadata:
      labels:
        kubernetes.azure.com/ebpf-dataplane: cilium
    spec:
      expireAfter: 720h
      nodeClassRef:
        group: karpenter.azure.com
        kind: AKSNodeClass
        name: my-node-class
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values:
            - amd64
        - key: kubernetes.io/os
          operator: In
          values:
            - linux
        - key: karpenter.sh/capacity-type
          operator: In
          values:
            - on-demand
        - key: karpenter.azure.com/sku-name
          operator: In
          values:
            - Standard_D8als_v6
            - Standard_E2ads_v6
        - key: topology.kubernetes.io/zone
          operator: In
          values:
            - canadacentral-1
            - canadacentral-2
            - canadacentral-3
      startupTaints:
        - effect: NoExecute
          key: node.cilium.io/agent-not-ready
          value: 'true'
"@

$NodePool | kubectl apply -f -

$NodePool = @"
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: my-node-pool-spot
spec:
  weight: 10
  disruption:
    budgets:
      - nodes: 30%
    consolidateAfter: 0s
    consolidationPolicy: WhenEmptyOrUnderutilized
  template:
    metadata:
      labels:
        kubernetes.azure.com/ebpf-dataplane: cilium
    spec:
      expireAfter: 720h
      nodeClassRef:
        group: karpenter.azure.com
        kind: AKSNodeClass
        name: my-node-class
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values:
            - amd64
        - key: kubernetes.io/os
          operator: In
          values:
            - linux
        - key: karpenter.sh/capacity-type
          operator: In
          values:
            - spot
      startupTaints:
        - effect: NoExecute
          key: node.cilium.io/agent-not-ready
          value: 'true'
"@

$NodePool | kubectl apply -f -

kubectl scale deployment nap-test-workload --replicas=15
kubectl get pods -w

kubectl get nodes -L karpenter.sh/capacity-type
```

## Karpenter Logs
```
kubectl get events -A --field-selector type=Warning,reportingComponent=karpenter --sort-by='.lastTimestamp'
```
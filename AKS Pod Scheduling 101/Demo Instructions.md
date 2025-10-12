## Define Variables
```
$AksName="pod-scheduling-aks"
$ResourceGroupName="pod-scheduling-rg"
$Location="CanadaCentral"
```

## Create AKS Cluster
```
az group create `
    --name $ResourceGroupName `
    --location $Location

az aks create `
    --name $AksName `
    --resource-group $ResourceGroupName `
    --node-count 2
    
az aks get-credentials `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing
```

# Quota
```
kubectl create ns quota
kubectl config set-context --current --namespace=quota
kubectl apply -f .\quotaCpu.yaml
kubectl get quota
kubectl apply -f .\podQuota.yaml

kubectl get pods
kubectl get quota
kubectl get replicaset
kubectl describe replicaset XXX
kubectl get quota

kubectl delete deployment whoami
kubectl delete quota cpu-quota
kubectl apply -f .\quotaPod.yaml
kubectl apply -f .\podQuota.yaml
kubectl get pods
kubectl get quota
```

# Node selector
```
kubectl create ns nodeselector
kubectl config set-context --current --namespace=nodeselector
kubectl get nodes --show-labels
```
Show labels in Azure portal

```
kubectl get nodes
kubectl label nodes XXX gpu=nvidia
kubectl apply -f .\podNodeSelector.yaml
kubectl describe pod whoami
```

# Affinity and anti-affinity
```
kubectl create ns affinity
kubectl config set-context --current --namespace=affinity
kubectl apply -f .\podAffinity.yaml
kubectl describe pod whoami
```

# Taints and Tolerations
```
kubectl create ns tolerations
kubectl config set-context --current --namespace=tolerations
kubectl get nodes
kubectl taint nodes XXX1 gpu=nvidia:NoSchedule
kubectl taint nodes XXX2 gpu=amd:NoSchedule
kubectl apply -f .\podTolerations.yaml
kubectl describe pod whoami
```

Update tolerations in podTolerations.yaml

```
kubectl delete pod whoami
kubectl apply -f .\podTolerations.yaml
kubectl describe pod whoami
```

# Pod Spread

Update to 5 nodes in Azure portal

```
kubectl get nodes
kubectl create ns pod-spread
kubectl config set-context --current --namespace=pod-spread
kubectl apply -f .\podTopologySpreadConstraints.yaml
kubectl get pods -o wide --sort-by=.spec.nodeName
```

Update replicas to 15

```
kubectl delete deployment whoami
kubectl apply -f .\podTopologySpreadConstraints.yaml
kubectl get pods -o wide --sort-by=.spec.nodeName
```
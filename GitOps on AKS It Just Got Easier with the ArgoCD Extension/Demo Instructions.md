az extension add -n k8s-configuration
az extension add -n k8s-extension

az extension update -n k8s-configuration
az extension update -n k8s-extension

az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.KubernetesConfiguration

az provider show -n Microsoft.KubernetesConfiguration -o table
az provider show -n Microsoft.ContainerService -o table
az provider show -n Microsoft.KubernetesConfiguration -o table

## Define Variables
```
$ResourceGroupName="argo-gitops"
$Location="CanadaCentral"
$AksName="gitops-demo-aks"

```

## Create RG and AKS Cluster
```
az group create `
    --name $ResourceGroupName `
    --location $Location

az aks create `
    --name $AksName `
    --resource-group $ResourceGroupName

az aks get-credentials `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing
```

## Deploy ArgoCD Extension
```
az k8s-extension create `
    --resource-group $ResourceGroupName `
    --cluster-name $AksName `
    --cluster-type managedClusters `
    --name argocd `
    --extension-type Microsoft.ArgoCD `
    --auto-upgrade false `
    --release-train preview `
    --version 0.0.7-preview `
    --config deployWithHightAvailability=false `
    --config namespaceInstall=false
```
last --config has a wrong - in docu

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

$Password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}")
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Password))

kubectl port-forward svc/argocd-server -n argocd 8080:443
localhost:8080

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: aks-store-demo
  namespace: argocd
spec:
  project: default
  source:    
      repoURL: https://github.com/Azure-Samples/aks-store-demo.git
      targetRevision: HEAD
      path: kustomize/overlays/dev
  syncPolicy:
      automated: {}
  destination:
      namespace: argocd
      server: https://kubernetes.default.svc
```

Foreground cascading deletion
In foreground cascading deletion, the owner object you're deleting first enters a deletion in progress state. In this state, the following happens to the owner object:

The Kubernetes API server sets the object's metadata.deletionTimestamp field to the time the object was marked for deletion.
The Kubernetes API server also sets the metadata.finalizers field to foregroundDeletion.
The object remains visible through the Kubernetes API until the deletion process is complete.

In background cascading deletion, the Kubernetes API server deletes the owner object immediately and the garbage collector controller (custom or default) cleans up the dependent objects in the background. If a finalizer exists, it ensures that objects are not deleted until all necessary clean-up tasks are completed. By default, Kubernetes uses background cascading deletion unless you manually use foreground deletion or choose to orphan the dependent objects.

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-demo
  namespace: argocd
spec:
  destination:
    namespace: argocd
    server: https://kubernetes.default.svc
  source:
    path: "GitOps on AKS It Just Got Easier with the ArgoCD Extension/Infrastructure"
    repoURL: https://github.com/WolfgangOfner/Youtube.git
    targetRevision: gitops-argo-youtube
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Update revisions and service
commit new changes
rollback in ArgoCD
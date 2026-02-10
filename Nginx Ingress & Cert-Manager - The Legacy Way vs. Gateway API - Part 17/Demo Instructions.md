## Define Variables
```
$AksName="nginx-ingress-aks"
$Location="CanadaCentral"
$ResourceGroupName="nginx-ingress-rg"

$IngressNamespace="nginx-ingress"
$CertManagerNamespace="cert-manager"
$DemoAppNamespace="demo-app"
```

## Create AKS
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

## Install Nginx-Ingress, Cert-Manager and ClusterIssuer
```
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install nginx-ingress ingress-nginx/ingress-nginx `
    --namespace $IngressNamespace `
    --create-namespace `
    --set controller.replicaCount=2 `
    --set controller.service.externalTrafficPolicy=Local `
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

$PublicIP = kubectl get svc nginx-ingress-ingress-nginx-controller -n $IngressNamespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Update DNS

```
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager `
  --namespace $CertManagerNamespace `
  --create-namespace `
  --set crds.enabled=true

$ClusterIssuer = @"
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    # server: https://acme-v02.api.letsencrypt.org/directory
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: <YOUR_EMAIL>
    privateKeySecretRef:
      name: letsencrypt
    solvers:
    - http01:
        ingress:
          class: nginx
"@

$ClusterIssuer | kubectl apply -f -
```

## Deploy Demo App
```
kubectl create ns $DemoAppNamespace

cd charts
code .
helm install ingressdemo ingressdemo -n $DemoAppNamespace

kubectl get certificate -n $DemoAppNamespace
kubectl describe certificate ingress-tls-secret -n $DemoAppNamespace

kubectl get secret -n $DemoAppNamespace
kubectl get certificaterequest -n $DemoAppNamespace
```

## Update ClusterIssuer to use Let's Encrypt Prod
```
$ClusterIssuer = @"
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    # server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: <YOUR_EMAIL>
    privateKeySecretRef:
      name: letsencrypt
    solvers:
    - http01:
        ingress:
          class: nginx
"@

$ClusterIssuer | kubectl apply -f -

kubectl delete secret ingress-tls-secret -n $DemoAppNamespace
kubectl delete certificaterequest ingress-tls-secret-1 -n $DemoAppNamespace

kubectl get secret -n $DemoAppNamespace
kubectl get certificaterequest -n $DemoAppNamespace
```
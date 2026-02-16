## Define Variables
```
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.NetworkFunction
az provider register --namespace Microsoft.ServiceNetworking

az provider show --namespace Microsoft.ContainerService -o table
az provider show --namespace Microsoft.Network -o table
az provider show --namespace Microsoft.NetworkFunction -o table
az provider show --namespace Microsoft.ServiceNetworking -o table

az extension add --name alb
az extension add --name aks-preview

az extension update --name alb
az extension update --name aks-preview

az feature register --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview"
az feature register --namespace "Microsoft.ContainerService" --name "ApplicationLoadBalancerPreview"
```

## Define Variables
```
$AksName="app-gateway-container-aks"
$Location="CanadaCentral"
$ResourceGroupName="app-gateway-container-rg"

$InfrastructureNamespace="gateway-infra"
$ApplicationLoadBalancerName="application-load-balancer"
$GatewayName="gateway"
$GatewayClassName="azure-alb-external"
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
  --enable-workload-identity `
  --enable-gateway-api `
  --enable-application-load-balancer 

az aks get-credentials `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --overwrite-existing
```

## Deploy Application Load Balancer
```
kubectl get pods -n kube-system

kubectl get gatewayclass $GatewayClassName -o yaml

kubectl get serviceaccount alb-controller-sa -n kube-system
```

Check Managed Identity and permissions + subnet

```
$McResourceGroup=$(az aks show `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --query "nodeResourceGroup" `
    --output tsv)

$AksVNetId=$(az network vnet list `
    --resource-group $McResourceGroup `
    --query '[0].id' `
    --output tsv)

$AlbSubnetId="${AksVNetId}/subnets/aks-appgateway"

kubectl create ns $InfrastructureNamespace

$ApplicationLoadBalancer = @"
apiVersion: alb.networking.azure.io/v1
kind: ApplicationLoadBalancer
metadata:
  name: $ApplicationLoadBalancerName
  namespace: $InfrastructureNamespace
spec:
  associations:
  - $AlbSubnetId
"@

$ApplicationLoadBalancer | kubectl apply -f -
```

It can take 5-6 minutes for the Application Gateway for Containers resources to be created.
The ApplicationLoadBalancer creates the Application Gateway for Containers resource but also a hidden data plan which is responsible for SSL termination and traffic routing.

```
kubectl get applicationloadbalancer $ApplicationLoadBalancerName -n $InfrastructureNamespace -o yaml --watch
```

If the reason and status of the ApplicationLoadBalancer do not change to "Ready" and "True", use the following code to check the logs
Note: Currently there are no pods running for the ALB when using the AKS addon.

```
kubectl get pods -n $InfrastructureNamespace
```

The Application Gateway for Container is now created

## Create Gateway
```
$Gateway = @"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: $GatewayName
  namespace: $InfrastructureNamespace
  annotations:
    alb.networking.azure.io/alb-namespace: $InfrastructureNamespace
    alb.networking.azure.io/alb-name: $ApplicationLoadBalancerName
spec:
  gatewayClassName: $GatewayClassName
  listeners:
  - name: http-listener
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
"@

$Gateway | kubectl apply -f -
```

## Get Hostname
```
kubectl get gateway $GatewayName -n $InfrastructureNamespace -o yaml -w
kubectl get gateway $GatewayName -n $InfrastructureNamespace -o jsonpath='{.status.addresses[0].value}'
```
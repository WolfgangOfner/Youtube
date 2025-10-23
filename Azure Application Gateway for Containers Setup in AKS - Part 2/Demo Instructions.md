## Define Variables
```
$AksName="app-gateway-container-aks"
$Location="CanadaCentral"
$ResourceGroupName="app-gateway-container-rg"

$AlbManagedIdentityName="azure-alb-identity" # name must be azure-alb-identity
$InfrastructureNamespace="alb-infra"
$ApplicationLoadBalancerName="application-load-balancer"
$GatewayName="gateway"
$GatewayClassName="azure-alb-external"
```

## Register Provider and install Extension
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
```

## Create AKS Cluster
```
az group create `
    --name $ResourceGroupName `
    --location $Location

az aks create `
    --name $AksName `
    --resource-group $ResourceGroupName `
    --network-plugin azure `
    --enable-oidc-issuer `
    --enable-workload-identity

az aks get-credentials `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing
```

## Install Helm
```
winget install helm.helm

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## Install ALB Controller
```
$McResourceGroup=$(az aks show `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --query "nodeResourceGroup" `
    --output tsv)

$McResourceGroupId=$(az group show `
    --name $McResourceGroup `
    --query id `
    --output tsv)

az identity create `
    --resource-group $ResourceGroupName `
    --name $AlbManagedIdentityName

$PrincipalId="$(az identity show `
    --resource-group $ResourceGroupName `
    --name $AlbManagedIdentityName `
    --query principalId `
    --output tsv)"
```

wait a minute to allow for replication of the identity

```
az role assignment create `
    --assignee-object-id $PrincipalId `
    --assignee-principal-type ServicePrincipal `
    --scope $McResourceGroupId `
    --role "Reader"

$AksOidcIssuer="$(az aks show `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --query "oidcIssuerProfile.issuerUrl" `
    --output tsv)"

az identity federated-credential create `
    --name "${AlbManagedIdentityName}-federatedIdentity" `
    --identity-name $AlbManagedIdentityName `
    --resource-group $ResourceGroupName `
    --issuer $AksOidcIssuer `
    --subject "system:serviceaccount:${InfrastructureNamespace}:alb-controller-sa"

helm install alb-controller oci://mcr.microsoft.com/application-lb/charts/alb-controller `
    --namespace $InfrastructureNamespace `
    --create-namespace `
    --version 1.7.9 `
    --skip-schema-validation `
    --set albController.namespace=$InfrastructureNamespace `
    --set albController.podIdentity.clientID=$(` 
        az identity show `
        --resource-group $ResourceGroupName `
        --name $AlbManagedIdentityName `
        --query clientId `
        --output tsv)

kubectl get pods -n $InfrastructureNamespace
kubectl get gatewayclass $GatewayClassName -o yaml
```

The ALB Controller is the link between Azure and AKS

## Create ApplicationLoadBalancer
```
$AksSubnetId=$(az vmss list `
    --resource-group $McResourceGroup `
    --query '[0].virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].ipConfigurations[0].subnet.id' `
    --output tsv)

$AksVnet=$(az network vnet show `
    --ids $AksSubnetId `
    --output json) | ConvertFrom-Json

$AksVnetName=$AksVnet.name
$AksVnetResourceGroup = $AksVnet.resourceGroup
$AksVnetId=$AksVnet.id

$SubnetAddressPrefix="10.225.0.0/24"
$AlbSubnetName="alb-subnet" 

az network vnet show `
    --resource-group $AksVnetResourceGroup `
    --name $AksVnetName `
    --query addressSpace.addressPrefixes

az network vnet subnet create `
    --resource-group $AksVnetResourceGroup `
    --vnet-name $AksVnetName `
    --name $AlbSubnetName `
    --address-prefixes $SubnetAddressPrefix `
    --delegations 'Microsoft.ServiceNetworking/trafficControllers'

$AlbSubnetId=$(az network vnet subnet show `
    --name $AlbSubnetName `
    --resource-group $AksVnetResourceGroup `
    --vnet-name $AksVnetName `
    --query '[id]' `
    --output tsv)

az role assignment create `
    --assignee-object-id $PrincipalId `
    --assignee-principal-type ServicePrincipal `
    --scope $McResourceGroupId `
    --role "AppGw for Containers Configuration Manager" 

az role assignment create `
    --assignee-object-id $PrincipalId `
    --assignee-principal-type ServicePrincipal `
    --scope $AlbSubnetId `
    --role "Network Contributor" 

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
The ApplicationLoadBalancer creates the Application Gateway for Containers resource but also a hidden data plan 
which is responsible for SSL termination and traffic routing.

```
kubectl get applicationloadbalancer $ApplicationLoadBalancerName -n $InfrastructureNamespace -o yaml --watch
```

If the reason and status of the ApplicationLoadBalancer do not change to "Ready" and "True", use the following code to check the logs

```
kubectl get pods -n $InfrastructureNamespace
kubectl logs alb-controller-XXX -n $InfrastructureNamespace
```

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
kubectl get gateway $GatewayName -n $InfrastructureNamespace -o yaml
kubectl get gateway $GatewayName -n $InfrastructureNamespace -o jsonpath='{.status.addresses[0].value}'
```
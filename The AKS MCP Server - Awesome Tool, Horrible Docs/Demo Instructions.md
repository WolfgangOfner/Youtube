## Define Variables
```powershell
$AksName="aks-mcp-aks"
$Location="CanadaCentral"
$ResourceGroupName="aks-mcp-rg"

$AksMcpManagedIdentity="aks-mcp-identity"
$AksMcpHelmDeploymentName="aks-mcp"
$AksMcpNamespace="aks-mcp"
$AksMcpServiceAccountName="aks-mcp"
$SubscriptionId=(az account show --query id -o tsv)
$TenantId=(az account show --query tenantId -o tsv)

$GatewayNamespace="envoy-gateway"
$GatewayName="gateway"
$GatewayClassName="envoy"
$DemoAppNamespace="demo-ns"
$DemoAppName="demo"
$DemoUrl="demo.programmingwithwolfgang.com"
```

## Create AKS
```powershell
az group create `
  --name $ResourceGroupName `
  --location $Location

az aks create `
  --name $AksName `
  --resource-group $ResourceGroupName `
  --enable-oidc-issuer `
  --enable-workload-identity

az aks get-credentials `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --overwrite-existing
```

## Configure Entra Workload ID for the MCP Server
```powershell
$AksMcpManagedIdentityClientId=$(`
  az identity create `
  --resource-group $ResourceGroupName `
  --name $AksMcpManagedIdentity `
  --query "clientId" `
  -o tsv)
  
$AksMcpManagedIdentityPrincipalId=$(`
  az identity show `
  --resource-group $ResourceGroupName `
  --name $AksMcpManagedIdentity `
  --query "principalId" `
  -o tsv)

az role assignment create `
  --role "Reader" `
  --assignee-object-id $AksMcpManagedIdentityPrincipalId `
  --assignee-principal-type ServicePrincipal `
  --scope "/subscriptions/$SubscriptionId"

$AksOidcIssuer=$(`
  az aks show `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --query "oidcIssuerProfile.issuerUrl" `
  -o tsv)

az identity federated-credential create `
  --name "aks-mcp-federated-credential" `
  --identity-name $AksMcpManagedIdentity `
  --resource-group $ResourceGroupName `
  --issuer $AksOidcIssuer `
  --subject "system:serviceaccount:${AksMcpNamespace}:${AksMcpServiceAccountName}" `
  --audience api://AzureADTokenExchange
```

## Deploy and test the MCP Server
```powershell
git clone https://github.com/Azure/aks-mcp.git
cd aks-mcp/chart

helm install $AksMcpHelmDeploymentName . `
  --namespace $AksMcpNamespace `
  --create-namespace `
  --set app.accessLevel=readonly `
  --set workloadIdentity.enabled=true `
  --set azure.clientId=$AksMcpManagedIdentityClientId `
  --set azure.subscriptionId=$SubscriptionId `
  --set azure.tenantId=$TenantId `
  --set "security.allowedHosts={localhost}" # last 2 not mentioned in docu

kubectl get pod -n $AksMcpNamespace

kubectl port-forward svc/$AksMcpHelmDeploymentName 8000:8000 -n $AksMcpNamespace
```

```yaml
{
  "servers": {
    "aks-mcp": {
      "type": "http",
      "url": "http://localhost:8000/mcp" # /mcp not mentioned in docu
    }
  }
}
```

Using the mcp server, can you tell me what namespaces do I have in my cluster?
Create a new namespace named my-namespace

```powershell
helm upgrade $AksMcpHelmDeploymentName . `
  --namespace $AksMcpNamespace `
  --reuse-values `
  --set app.accessLevel=admin

kubectl port-forward svc/$AksMcpHelmDeploymentName 8000:8000 -n $AksMcpNamespace
```

Create a new namespace named my-namespace

What resources do I have in my subscription?
What nodes does the cluster have?
Scale the node pool to two nodes

```powershell
az role assignment delete `
  --role "Reader" `
  --assignee-object-id $AksMcpManagedIdentityPrincipalId `
  --scope "/subscriptions/$SubscriptionId"

az role assignment create `
  --role "Contributor" `
  --assignee-object-id $AksMcpManagedIdentityPrincipalId `
  --assignee-principal-type ServicePrincipal `
  --scope "/subscriptions/$SubscriptionId"

kubectl port-forward svc/$AksMcpHelmDeploymentName 8000:8000 -n $AksMcpNamespace
```

Scale the node pool to two nodes
What nodes does the cluster have?
What Kubernetes version is the cluster using?
Upgrade the Kubernetes version to 1.36.0
The connection was lost due to the upgrade. can you check if it is complete and if not, wait until it is complete?

## Deploy Envoy and create the Gateway and GatewayClass
```powershell
helm install envoy oci://docker.io/envoyproxy/gateway-helm `
  --version v1.8.2 `
  --namespace $GatewayNamespace `
  --create-namespace

$GatewayClass = @"
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: $GatewayClassName
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
"@

$GatewayClass | kubectl apply -f -

$Gateway = @"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: $GatewayName
  namespace: $GatewayNamespace
spec:
  gatewayClassName: $GatewayClassName
  allowedListeners:
    namespaces:
      from: All
  listeners:
  - name: http-listener
    port: 80
    protocol: HTTP
"@

$Gateway | kubectl apply -f -

kubectl get gateway -n $GatewayNamespace
```

might take a minute to switch Programmed = True

```powershell
kubectl get gatewayclass

$Fqdn=$(kubectl get gateway $GatewayName -n $GatewayNamespace -o jsonpath='{.status.addresses[0].value}')
```

Update DNS

## Deploy the Test App and let the AI fix it with the MCP Server
```powershell
kubectl create ns $DemoAppNamespace

kubectl run $DemoAppName `
  --image=traefik/whoami `
  --expose `
  --port=80 `
  --namespace=$DemoAppNamespace

$ListenerSet = @"
apiVersion: gateway.networking.k8s.io/v1
kind: ListenerSet
metadata:
  name: "${DemoAppName}-listener"
  namespace: $DemoAppNamespace
spec:
  parentRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: $GatewayName
    namespace: $GatewayNamespace
  listeners:
    - name: http-traefik
      protocol: HTTP
      port: 80
      hostname: $DemoUrl
"@

$ListenerSet | kubectl apply -f -

kubectl get listenerset -n $DemoAppNamespace

$DemoUrl

kubectl port-forward svc/$AksMcpHelmDeploymentName 8000:8000 -n $AksMcpNamespace
```

I have an app in the demo-ns but I receive a 404 error when I enter the url http://demo.programmingwithwolfgang.com. Can you figure out what the problem is and fix it?

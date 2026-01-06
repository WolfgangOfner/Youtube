## Define Variables
```
$AlbManagedIdentityName="azure-alb-identity"
$ResourceGroupName="app-gateway-container-rg"

$InfrastructureNamespace="alb-infra"
$GatewayName="gateway"

$WafPolicy="waf-policy"
$SubscriptionId="$(az account show --query id --output tsv)"
```

## Configure Permissions and create a WAF Policy
```
$PrincipalId="$(az identity show `
    --resource-group $ResourceGroupName `
    --name $AlbManagedIdentityName `
    --query principalId `
    --output tsv)"
```

The role assignment needs to be at least on the WAF policy. The next command assigns the permission on the RG which makes managing multiple WAF policies easier. 

```
az role assignment create `
    --assignee-object-id $PrincipalId `
    --role "Network Contributor" `
    --scope /subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName `
    --assignee-principal-type ServicePrincipal

az network application-gateway waf-policy create `
    --name $WafPolicy `
    --resource-group $ResourceGroupName
```

## Apply the WAF Policy to the entire Gateway
```
$WebApplicationFirewallPolicy = @"
apiVersion: alb.networking.azure.io/v1
kind: WebApplicationFirewallPolicy
metadata:
  name: $WafPolicy
  namespace: $InfrastructureNamespace
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: $GatewayName
    namespace: $InfrastructureNamespace
  webApplicationFirewall:
    id: /subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies/$WafPolicy
"@

$WebApplicationFirewallPolicy | kubectl apply -f -

kubectl get WebApplicationFirewallPolicy -n $InfrastructureNamespace

kubectl describe WebApplicationFirewallPolicy $WafPolicy -n $InfrastructureNamespace

kubectl delete WebApplicationFirewallPolicy $WafPolicy -n $InfrastructureNamespace
```

## Apply the WAF Policy only to one HTTP Listener
```
kubectl get gateway $GatewayName -n $InfrastructureNamespace
kubectl describe gateway $GatewayName -n $InfrastructureNamespace

$WebApplicationFirewallPolicy = @"
apiVersion: alb.networking.azure.io/v1
kind: WebApplicationFirewallPolicy
metadata:
  name: $WafPolicy
  namespace: $InfrastructureNamespace
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: $GatewayName
    namespace: $InfrastructureNamespace
    sectionNames: ["traefik-https-listener"]
  webApplicationFirewall:
    id: /subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies/$WafPolicy
"@

$WebApplicationFirewallPolicy | kubectl apply -f -

kubectl delete WebApplicationFirewallPolicy $WafPolicy -n $InfrastructureNamespace
```
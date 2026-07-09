## Define Variables
```
$AksName="egress-aks"
$Location="CanadaCentral"
$ResourceGroupName="egress-rg"

$NatPipName="egress-natgw-pip"
$DemoAppNamespace="demo-ns"
$DemoAppName="egress-tester"
```

## One-time: Install aks-preview and register the feature flag
```
az extension add --name aks-preview
az extension update --name aks-preview

az feature register `
  --namespace "Microsoft.ContainerService" `
  --name "ManagedNATGatewayV2Preview"

az feature show `
  --namespace "Microsoft.ContainerService" `
  --name "ManagedNATGatewayV2Preview" `
  --query "properties.state" `
  -o tsv

az provider register --namespace Microsoft.ContainerService
```

## Create the StandardV2 Public IP
```
az group create `
  --name $ResourceGroupName `
  --location $Location

$NatPipId = az network public-ip create `
  --resource-group $ResourceGroupName `
  --name $NatPipName `
  --location $Location `
  --sku StandardV2 `
  --allocation-method Static `
  --version IPv4 `
  --zone 1 2 3 `
  --query "publicIp.id" `
  -o tsv
```

## Create the AKS Cluster with `managedNATGatewayV2`
```
az aks create `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --location $Location `
  --outbound-type managedNATGatewayV2 `
  --nat-gateway-outbound-ips $NatPipId `
  --nat-gateway-idle-timeout 4

az aks get-credentials `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --overwrite-existing

az aks show `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --query "networkProfile.{outboundType:outboundType, natGatewayProfile:natGatewayProfile}" `
  -o jsonc
```

## Capture the expected egress IP
```
$ExpectedIp = az network public-ip show `
  --resource-group $ResourceGroupName `
  --name $NatPipName `
  --query "ipAddress" `
  -o tsv

$ExpectedIp"
```

## Deploy the Test Workload
```
kubectl create ns $DemoAppNamespace

kubectl run $DemoAppName `
  --image=curlimages/curl `
  --namespace=$DemoAppNamespace `
  --command -- sleep infinity

kubectl -n $DemoAppNamespace wait --for=condition=Ready pod/$DemoAppName --timeout=120s
```

## Verify egress leaves via the NAT Gateway v2 IP
```
$Observed = kubectl -n $DemoAppNamespace exec $DemoAppName -- curl -s https://ifconfig.me/ip

Write-Host "Observed egress IP: $Observed"
Write-Host "Expected egress IP: $ExpectedIp"
```
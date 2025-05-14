## Define Variables
```
$ResourceGroupName="MyResourceGroup"
$AksName="Aks-Cluster"
$Location="CanadaCentral"
```

## Create AKS 
```
az group create `
  --name $ResourceGroupName `
  --location $Location

az aks create `
  --resource-group $ResourceGroupName `
  --name $AksName

az aks get-credentials `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --overwrite-existing
```
## Deploy LoadBalancer with Public IP
```
kubectl create ns internal-lb
kubectl config set-context --current --namespace=internal-lb
kubectl apply -f deployment.yaml
kubectl apply -f service-external.yaml
kubectl get all
curl http://External_IP
```
## Change Service to Internal Load Balancer
```
kubectl apply -f service-internal.yaml
kubectl get service nginx-service
```

## Set IP for Service
```
kubectl apply -f service-internal-ip.yaml
kubectl get service nginx-service
```

## Create VM in the AKS VNet
```
$AksMcRg=$(`
  az aks show `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --query nodeResourceGroup `
  --output tsv)

$AksVNetSubnetId=$(`
  az network vnet list `
  --resource-group $AksMcRg `
  --query [].subnets[].id `
  --output tsv)

$AksNsgName=$(az network nsg list -g $AksMcRg --query [0].name)
```
The NSG is necessary because the AKS VNet does not allow SSH

```
az network nsg rule create `
  --resource-group $AksMcRg `
  --nsg-name $AksNsgName `
  --name allow-SSH `
  --priority 1000 `
  --source-address-prefixes '*' `
  --destination-port-ranges 22 `
  --protocol TCP `
  --access Allow

$VmNameLinuxSameVnet="ubuntu-same-vnet-vm"
$VmAdmin="wolfgang"
$VmPassword="MyVerySecretPw1!"

$VmPublicIp=$(`
  az vm create `
  --name $VmNameLinuxSameVnet `
  --resource-group $ResourceGroupName `
  --image Ubuntu2404 `
  --admin-username $VmAdmin `
  --admin-password $VmPassword `
  --security-type TrustedLaunch `
  --subnet $AksVNetSubnetId `
  --query publicIpAddress  `
  --output tsv)

kubectl get service nginx-service --> copy external ip
```

## Connect to the VM and access the AKS Service
```
ssh $VmAdmin@$VmPublicIp

curl http://10.224.0.22
```

## Create new VNet and deploy VM into it
```
$VnetName="MyVNet"
$SubnetName="MySubnet"
$VmNameLinuxOtherVnet="ubuntu-other-vnet-vm"

az network vnet create `
--resource-group $ResourceGroupName `
--name $VnetName `
--location $Location `
--address-prefix 192.168.0.0/16 `
--subnet-name $SubnetName `
--subnet-prefixes 192.168.0.0/24 

$VmPublicIp=$(`
  az vm create `
  --name $VmNameLinuxOtherVnet `
  --resource-group $ResourceGroupName `
  --image Ubuntu2404 `
  --admin-username $VmAdmin `
  --admin-password $VmPassword `
  --security-type TrustedLaunch `
  --vnet-name $VnetName `
  --subnet $SubnetName `
  --query publicIpAddress  `
  --output tsv)
```

## Create Private Link Service, link it to a Private Endpoint and attach it the VNet
```
kubectl apply -f service-internal-pls.yaml
kubectl get service nginx-service

az network private-link-service list `
  --resource-group $AksMcRg `
  --query "[].{Name:name,Alias:alias}" `
  --output table

$AksPlsId=$(`
  az network private-link-service list `
  --resource-group $AksMcRg `
  --query "[].id" `
  --output tsv)

az network private-endpoint create `
  --resource-group $ResourceGroupName `
  --name nginxAksServicePe `
  --vnet-name $VnetName `
  --subnet $SubnetName `
  --private-connection-resource-id $AksPlsId `
  --connection-name connectToNginxAksService

$PeNicId=$(`
  az network private-endpoint show `
  --name nginxAksServicePe `
  --resource-group $ResourceGroupName `
  --query "networkInterfaces[0].id")

az network nic show `
  --ids $PeNicId `
  --query "ipConfigurations[0].privateIPAddress"
```

## Connect to the VM and test the access to the AKS Service
```
ssh $VmAdmin@$VmPublicIp

curl http://192.168.0.5
```
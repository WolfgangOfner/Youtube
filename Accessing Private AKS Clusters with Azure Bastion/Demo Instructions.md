## Define Variables
```
$ResourceGroupName="private-cluster-rg"
$Location="CanadaCentral"
$BastionPublicIPName="BastionPublicIP"
$VnetName="MyVNet"
$AksName="private-aks-cluster"
$BastionName="BastionDemo"
```

## Create AKS
```
az group create `
  --name $ResourceGroupName `
  --location $Location

az aks create `
  --name $AksName `
  --resource-group $ResourceGroupName `
  --enable-private-cluster `
  --no-wait
```

## Create VNet for Bastion and VM
```
az network public-ip create `
  --resource-group $ResourceGroupName `
  --name $BastionPublicIPName `
  --version IPv4 `
  --sku Standard `
  --zone 1 2 3

  az network vnet create `
  --resource-group $ResourceGroupName `
  --name $VnetName `
  --location $Location `
  --address-prefix 10.0.0.0/16 `
  --subnet-name MySubnet `
  --subnet-prefixes 10.0.0.0/24  

$VnetId=$(`
  az network vnet show `
  --resource-group $ResourceGroupName `
  --name $VnetName `
  --query id -o tsv)

az network vnet subnet create `
  --resource-group $ResourceGroupName `
  --name AzureBastionSubnet `
  --vnet-name $VnetName `
  --address-prefixes 10.0.200.0/24 
```

## Create Bastion
```
az network bastion create `
  --location $Location `
  --name $BastionName `
  --public-ip-address $BastionPublicIPName `
  --resource-group $ResourceGroupName `
  --vnet-name $VnetName `
  --no-wait
```

## Create VM
```
$VmNameLinux="ubuntu-vm"
$VmAdmin="wolfgang"
$VmPassword="MyVerySecretPw1!"


$VmId=$(`
  az vm create `
  --name $VmNameLinux `
  --resource-group $ResourceGroupName `
  --image Ubuntu2404 `
  --admin-username $VmAdmin `
  --admin-password $VmPassword `
  --security-type TrustedLaunch `
  --vnet-name $VnetName `
  --subnet MySubnet `
  --public-ip-address '""' `
  --query id -o tsv)
```

## Connect to the VM via Bastion
- Connect using the azure portal
- Enable native client support in Bastion

## Connect to the VM via Bastion
```
az network bastion ssh `
  --name $BastionName `
  --resource-group $ResourceGroupName `
  --target-resource-id $VmId `
  --auth-type "password" `
  --username $VmAdmin 
```

## Install Azure CLI and kubectl
```
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
sudo snap install kubectl --classic
kubectl version --client
```

## Try to access AKS
```
ResourceGroupName="private-cluster-rg"
AksName="private-aks-cluster"

az login

az aks get-credentials \
  --resource-group $ResourceGroupName \
  --name $AksName \
  --overwrite-existing

kubectl get ns
```
## Configure Peering and DNS registration

Replace --zone name with the name of your private DNS zone

```
az network private-dns link vnet create `
  --name $VnetName `
  --resource-group "MC_$($ResourceGroupName)_$($AksName)_$($Location)" `
  --virtual-network $VnetId `
  --zone-name b4a1f22c-5d21-4eaa-bc2c-68060d24fc64.privatelink.canadacentral.azmk8s.io ` 
  --registration-enabled true
```

VNet peering (MyVNet to AKS is enough) + private DNS Zone link

Command does not work --> required remote sync and is stuck in the "Initiated" state

```
az network vnet peering create `
  --resource-group $ResourceGroupName `
  --name MyVnet-AKS `
  --vnet-name $VnetName `
  --remote-vnet <AksVnetName> `
  --allow-vnet-access true
```

## Connect to VM and access AKS
```
az network bastion ssh `
  --name $BastionName `
  --resource-group $ResourceGroupName `
  --target-resource-id $VmId `
  --auth-type "password" `
  --username $VmAdmin 

kubectl get ns
```
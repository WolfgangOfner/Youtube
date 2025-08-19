## Define Variables 
```
$AksName="private-aks-cluster"
$ResourceGroupName="private-cluster-rg"
$Location="CanadaCentral"
$BastionPublicIPName="BastionPublicIP"
$BastionName="BastionDemo"
$VnetName="BastionDemo-vnet"
```

## Create AKS
```
az group create `
    --name $ResourceGroupName `
    --location $Location

az aks create `
    --name $AksName `
    --resource-group $ResourceGroupName `
    --enable-private-cluster

az aks get-credentials `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing

kubectl get ns
```

## Configure Bastion Vnet
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
  --query id `
  --output tsv)

az network vnet subnet create `
  --resource-group $ResourceGroupName `
  --name AzureBastionSubnet `
  --vnet-name $VnetName `
  --address-prefixes 10.0.200.0/24 
```

## Create Bastion
```
$BastionId=$(az network bastion create `
  --location $Location `
  --name $BastionName `
  --public-ip-address $BastionPublicIPName `
  --resource-group $ResourceGroupName `
  --vnet-name $VnetName `
  --enable-tunneling true `
  --query id `
  --output tsv)
```

## Configure VNet Peering
```
$AksMcRgName="MC_$($ResourceGroupName)_$($AksName)_$($Location)"

$AksVnetId=$(az network vnet list `
  --resource-group $AksMcRgName `
  --query [0].id `
  --output tsv)

az network vnet peering create `
  --resource-group $ResourceGroupName `
  --name MyVnet-AKS `
  --vnet-name $VnetName `
  --remote-vnet $AksVnetId `
  --allow-vnet-access true `
  --peer-complete-vnets true
```

## Connect to private AKS through Bastion
```
az aks bastion `
  --name $AksName `
  --resource-group $ResourceGroupName `
  --bastion $BastionId
```

Install aks-preview extension if promted
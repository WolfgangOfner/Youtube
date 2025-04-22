## Define Variables
```
$ResourceGroupName="mdp-vnet-demo-rg"
$Location="CanadaCentral"
$VnetName="MyVNet"
$SubnetName="MDP-demo-subnet"
$SubscriptionId="$(az account show --query id --output tsv)"

$PoolName="MDP-VNet-Demo"
$DevCenterName="DevOpsPoolDevCenter"
$DevCenterProject="DevOpsPoolProject"

$KeyVaultName="wolfgangmdpdemokv" # name must be unique
$PrivateEndpointName="MyPrivateEndpoint"
$PrivateDnsName="privatelink.vaultcore.azure.net"
```

## Create resource group, VNet with subnets and key vault
```
az group create `
  --name $ResourceGroupName `
  --location $Location

az network vnet create `
  --resource-group $ResourceGroupName `
  --name $VnetName `
  --location $Location `
  --address-prefix 10.0.0.0/16 `
  --subnet-name $SubnetName `
  --subnet-prefixes 10.0.0.0/24 

$SubnetId=$(`
  az network vnet subnet create `
  --resource-group $ResourceGroupName `
  --name mdp-subnet `
  --vnet-name $VnetName `
  --address-prefixes 10.0.200.0/24 `
  --delegations Microsoft.DevOpsInfrastructure/pools `
  --query id -o tsv)

$DevOpsInfrastructureSpId=$(`
  az ad sp list `
  --display-name "DevOpsInfrastructure" `
  --query [0].id `
  --output tsv)

az role assignment create `
  --assignee $DevOpsInfrastructureSpId `
  --role Reader `
  --scope /subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/virtualNetworks/$VnetName

az role assignment create `
  --assignee $DevOpsInfrastructureSpId `
  --role "Network Contributor" `
  --scope /subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/virtualNetworks/$VnetName

az keyvault create `
  --resource-group $ResourceGroupName `
  --name $KeyVaultName `
  --location $Location `
  --enable-rbac-authorization true `
  --public-network-access Disabled `
  --bypass None
```
Replace --assignee with the ID of your Service Connection

```
az role assignment create `
  --role "Key Vault Secrets Officer" `
  --assignee 7b45af52-eb3c-4fe6-a58a-2f809a71e9cd `
  --scope /subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.KeyVault/vaults/$KeyVaultName
```

## Create private DNS-Zone and private endpoint
```
az network private-dns zone create `
  --resource-group $ResourceGroupName `
  --name $PrivateDnsName

az network private-dns link vnet create `
  --resource-group $ResourceGroupName `
  --virtual-network $VnetName `
  --zone-name $PrivateDnsName `
  --name $VnetName `
  --registration-enabled true

  az network private-endpoint create `
  --resource-group $ResourceGroupName `
  --location $Location `
  --vnet-name $VnetName `
  --subnet $SubnetName `
  --name $PrivateEndpointName `
  --private-connection-resource-id "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.KeyVault/vaults/$KeyVaultName" `
  --group-ids vault `
  --connection-name MyPrivateLinkConnectionName

az network private-endpoint dns-zone-group create `
  --name default `
  --endpoint-name $PrivateEndpointName `
  --private-dns-zone $PrivateDnsName `
  --resource-group $ResourceGroupName `
  --zone-name privatelink-vaultcore-azure-net
```

## Create Managed DevOps Pool
```
$DevCenterId=$( ` 
  az devcenter admin devcenter create `
  --name $DevCenterName `
  --resource-group $ResourceGroupName `
  --location $Location `
  --query id `
  --output tsv)

$DevCenterProjectId=$( `
  az devcenter admin project create `
  --name $DevCenterProject `
  --description "Youtube Dev Center Demo" `
  --resource-group $ResourceGroupName `
  --location $Location `
  --dev-center-id $DevCenterId `
  --query id `
  --output tsv)

```
replace subnetId in fabric-profile.json
```

az mdp pool create `
  --name $PoolName `
  --resource-group $ResourceGroupName `
  --location $Location `
  --devcenter-project-id $DevCenterProjectId `
  --maximum-concurrency 1 `
  --agent-profile agent-profile.json `
  --fabric-profile fabric-profile.json `
  --organization-profile organization-profile.json    
```
## Deploy AKS on on-prem Ubuntu with Deployment Script
VM name must be 3-63 characters long
```bash
curl -sSL https://aka.ms/aksbm | bash -s -- \
  -s <SubscriptionId> \
  -t <TenantId>
```

## Connect to the on-prem AKS Cluster
```powershell
$ClusterName="aks-on-prem-cluster"
$ResourceGroup="aks-on-prem-rg"

az aksarc get-credentials `
  --name $ClusterName `
  --resource-group $ResourceGroup `
  --overwrite-existing

# az connectedk8s proxy --name $ClusterName --resource-group $ResourceGroup

kubectl get nodes

kubectl get ns
```

## Prepare Azure VM
```bash
export MSFT_ARC_TEST=true
sudo systemctl set-environment MSFT_ARC_TEST=true

sudo systemctl stop walinuxagent
sudo systemctl disable walinuxagent

sudo ufw --force enable
sudo ufw deny out from any to 169.254.169.254
sudo ufw default allow incoming

sudo iptables -I OUTPUT 1 -d 169.254.169.254 -j REJECT
```

## Prepare Ubuntu and Azure Subscription
```bash

curl -fsSL 'https://azurecliprod.blob.core.windows.net/$root/deb_install.sh' | sudo bash

az login

az feature register --namespace Microsoft.HybridConnectivity --name hiddenPreviewAccess

az provider register --namespace Microsoft.HybridCompute
az provider register --namespace Microsoft.HybridContainerService
az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.ExtendedLocation
az provider register --namespace Microsoft.HybridConnectivity
az provider register --namespace Microsoft.AzureStackHCI

az provider show --namespace Microsoft.AzureStackHCI --query "registrationState"

cd /tmp
source /etc/os-release
curl -sSL -O https://packages.microsoft.com/config/$ID/$VERSION_ID/packages-microsoft-prod.deb

sudo apt install ./packages-microsoft-prod.deb

rm packages-microsoft-prod.deb

sudo apt update && sudo apt install azcmagent
```

## Define Variables
```bash
Location="eastus"  # only eastus is supported at the moment
MachineName="$HOSTNAME"
ClusterName="$HOSTNAME"-cluster
ResourceGroup="aks-on-prem-ubuntu-rg"
SubscriptionId=$(az account show --query id --output tsv)
TenantId=$(az account show --query tenantId --output tsv)
```

## Install Azure Arc
```bash
az group create \
  --name $ResourceGroup \
  --location $Location

sudo azcmagent connect \
  --resource-group $ResourceGroup \
  --location $Location \
  --subscription-id $SubscriptionId \
  --cloud "AzureCloud" \
  --tags 'ArcSQLServerExtensionDeployment=Disabled'
```

## Deploy AKS on Ubuntu
VM name must be 3-63 characters long
```bash
az extension add --name aksarc --upgrade --allow-preview true

az aksarc deploy \
  --resource-group $ResourceGroup \
  --arc-machine-names $MachineName
```

## Connect to the Azure VM AKS Cluster
```powershell
$ClusterName="aks-on-prem-cloud-cluster"
$ResourceGroup="aks-on-prem-ubuntu-rg"

az aksarc get-credentials `
  --name $ClusterName `
  --resource-group $ResourceGroup `
  --overwrite-existing

az connectedk8s proxy `
  --name $ClusterName `
  --resource-group $ResourceGroup

kubectl get nodes

kubectl get ns
```

## Remove AKS
```bash
az aksarc undeploy \
  --resource-group $ResourceGroup \
  --arc-machine-names aks-on-prem-cloud \
  --yes
```
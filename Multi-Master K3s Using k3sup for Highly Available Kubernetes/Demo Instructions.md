$Location="CanadaCentral"
$ResourceGroupName="k3s-demo"
$VnetName = "k3s-vnet"

$VmNameManagement="k3s-management"
$VmNameOne="k3s-one"
$VmNameTwo="k3s-two"
$VmNameThree="k3s-three"
$VmPrivateIpOne="10.0.0.100"
$VmPrivateIpTwo="10.0.0.101"
$VmPrivateIpThree="10.0.0.102"
$VmImage="Canonical:ubuntu-24_04-lts:server:latest"
$VmSize="Standard_D2s_v5"
$VmAdmin="wolfgang"
$VmPassword="MySecurePassword1!"

az group create `
   --name $ResourceGroupName `
   --location $Location

az network vnet create `
   --resource-group $ResourceGroupName `
   --name $VnetName `
   --subnet-name default

az network nic create `
   --resource-group $ResourceGroupName `
   --name "$VmNameOne-NIC" `
   --vnet-name $VnetName `
   --subnet default `
   --private-ip-address $VmPrivateIpOne

az network nic create `
   --resource-group $ResourceGroupName `
   --name "$VmNameTwo-NIC" `
   --vnet-name $VnetName `
   --subnet default `
   --private-ip-address $VmPrivateIpTwo

az network nic create `
   --resource-group $ResourceGroupName `
   --name "$VmNameThree-NIC" `
   --vnet-name $VnetName `
   --subnet default `
   --private-ip-address $VmPrivateIpThree

$VmPublicIpManagemet=$(az vm create `
   --resource-group $ResourceGroupName `
   --name $VmNameManagement `
   --image $VmImage `
   --location $Location `
   --size $VmSize `
   --admin-username $VmAdmin `
   --admin-password $VmPassword `
   --public-ip-sku Standard `
   --vnet-name $VnetName `
   --subnet default `
   --authentication-type password `
   --query 'publicIpAddress' `
   --output tsv)

az vm create `
   --resource-group $ResourceGroupName `
   --name $VmNameOne `
   --image $VmImage `
   --location $Location `
   --size $VmSize `
   --admin-username $VmAdmin `
   --admin-password $VmPassword `
   --nics "$VmNameOne-NIC" `
   --authentication-type password `
   --no-wait

az vm create `
   --resource-group $ResourceGroupName `
   --name $VmNameTwo `
   --image $VmImage `
   --location $Location `
   --size $VmSize `
   --admin-username $VmAdmin `
   --admin-password $VmPassword `
   --nics "$VmNameTwo-NIC" `
   --authentication-type password `
   --no-wait

az vm create `
   --resource-group $ResourceGroupName `
   --name $VmNameThree `
   --image $VmImage `
   --location $Location `
   --size $VmSize `
   --admin-username $VmAdmin `
   --admin-password $VmPassword `
   --nics "$VmNameThree-NIC" `
   --authentication-type password `
   --no-wait

ssh $VmAdmin@$VmPublicIpManagemet

mkdir ~/.kube
sudo snap install kubectl --classic

curl -sLS https://get.k3sup.dev | sh
sudo install k3sup /usr/local/bin/

k3sup version

sudo visudo
wolfgang ALL=(ALL) NOPASSWD: ALL

dir /home/wolfgang/.ssh
ssh-keygen -t ed25519 -C "k3s-management-key"
dir /home/wolfgang/.ssh

VmAdmin="wolfgang"
VmPrivateIpOne="10.0.0.100"
VmPrivateIpTwo="10.0.0.101"
VmPrivateIpThree="10.0.0.102"
MySecurePassword1!

ssh-copy-id $VmAdmin@$VmPrivateIpOne
ssh-copy-id $VmAdmin@$VmPrivateIpTwo
ssh-copy-id $VmAdmin@$VmPrivateIpThree

k3sup install \
  --ip $VmPrivateIpOne \
  --user $VmAdmin \
  --cluster \
  --ssh-key /home/wolfgang/.ssh/id_ed25519 \
  --k3s-version v1.33.9+k3s1 \
  --merge \
  --local-path $HOME/.kube/config \
  --context my-k3s

kubectl get node

k3sup join \
  --ip $VmPrivateIpTwo \
  --user $VmAdmin \
  --server-user $VmAdmin \
  --server-ip $VmPrivateIpOne \
  --server \
  --ssh-key /home/wolfgang/.ssh/id_ed25519 \
  --k3s-version v1.33.9+k3s1

k3sup join \
  --ip $VmPrivateIpThree \
  --user $VmAdmin \
  --server-user $VmAdmin \
  --server-ip $VmPrivateIpOne \
  --server \
  --ssh-key /home/wolfgang/.ssh/id_ed25519 \
  --k3s-version v1.33.9+k3s1

  kubectl get nodes -o wide --sort-by='.status.addresses[?(@.type=="InternalIP")].address'
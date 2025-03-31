## Define Variables
```
$ResourceGroup="mdp-custom-image-rg"
$Location="CanadaCentral"
$Gallery="Gallery"
```

## Create an Azure Compute Gallery
```
az group create --name $ResourceGroup --location $Location

$GalleryId=$(`
    az sig create `
    --resource-group $ResourceGroup `
    --gallery-name $Gallery `
    --query id -o tsv)

$DevOpsInfrastructureId=$(`
    az ad sp list `
    --filter "displayname eq 'DevOpsInfrastructure'" `
    --query "[].id" --output tsv)

az role assignment create `
    --assignee $DevOpsInfrastructureId `
    --role "Reader" `
    --scope $GalleryId   
```

Your MDP deployment with the custom image will fail without a useful error message if you do not set the Reader role

## Create a dev center
```
$DevCenterName="DevOpsPoolDevCenter"
$DevCenterProject="DevOpsPoolProject"

az devcenter admin devcenter create `
    --name $DevCenterName `
    --resource-group $ResourceGroup `
    --location $Location
```

## Save the id of the newly created dev center
```
$DevCenterId=$( `
    az devcenter admin devcenter show `
    --name $DevCenterName `
    --resource-group $ResourceGroup `
    --query id -o tsv)
```

## Create a dev center project
```
az devcenter admin project create `
    --name $DevCenterProject `
    --description "Custom Image Dev Center Demo" `
    --resource-group $ResourceGroup `
    --location $Location `
    --dev-center-id $DevCenterId
```

## Create Linux VM, install Docker and prepare Image
```
$VmNameLinux="ubuntu-vm"
$VmAdmin="wolfgang"
$VmPassword="MyVerySecretPw1!"

$PublicIpLinux=$(`
    az vm create `
    --name $VmNameLinux `
    --resource-group $ResourceGroup `
    --image Ubuntu2404 `
    --admin-username $VmAdmin `
    --admin-password $VmPassword `
    --security-type TrustedLaunch `
    --query publicIpAddress -o tsv)

ssh wolfgang@$PublicIpLinux

curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh ./get-docker.sh
sudo docker ps

exit

az vm deallocate `
    --resource-group $ResourceGroup `
    --name $VmNameLinux  

az vm generalize `
    --resource-group $ResourceGroup `
    --name $VmNameLinux
```

## Capture the VM
Capture the VM in the portal and create a new image definition in the previously created gallery

## Create the Managed DevOps Pool in the portal
Use the previously created Dev Center project to create a new Managed DevOps Pool
- URL: programmingwithwolfgang
- Pool name: Ubuntu-MDP

## Test the pipeline
Run the pipeline with your agent pool name

## Create Windows VM, install .NET 9 and prepare Image
```
$VmNameWindows="windows-vm"
$VmAdmin="wolfgang"
$VmPassword="MyVerySecretPw1!"

$PublicIpWindows=$(`
    az vm create `
    --name $VmNameWindows `
    --resource-group $ResourceGroup `
    --image Win2022Datacenter `
    --admin-username $VmAdmin `
    --admin-password $VmPassword `
    --security-type TrustedLaunch `
    --size Standard_D4ads_v5 `
    --query publicIpAddress -o tsv)

mstsc.exe /v:$PublicIpWindows

Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

choco install dotnet-9.0-sdk -y
rm C:\Windows\Panther -r -force

REM Enable CD/DVD-ROM
reg add HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\cdrom /v start /t REG_DWORD /d 1 /f

cd %windir%\system32\sysprep
sysprep.exe /generalize /shutdown

az vm generalize `
    --resource-group $ResourceGroup `
    --name $VmNameWindows
```

## Capture the VM
Capture the VM in the portal and create a new image definition in the previously created gallery

## Create the Managed DevOps Pool in the portal
Use the previously created Dev Center project to create a new Managed DevOps Pool
- URL: programmingwithwolfgang
- Pool name: Windows-MDP

## Test the pipeline
Run the pipeline with your agent pool name
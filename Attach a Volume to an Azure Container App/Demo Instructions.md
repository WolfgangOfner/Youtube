## Define Variables
```
$ResourceGroup="aca-storage-demo"
$Location="canadacentral" 
$Environment="devops-agent-aca-env"
$ContainerAppName="azure-pipelines-agent"
$ContainerImageName="wolfgangofner/adoagent" 
$StorageAccountName="wolfgangcaadoagent" # must be unique world-wide
$StorageShareName="adoagentfileshare"
$StorageMountName="adoagentstoragemount"

$AzpPool="AgentInContainer" # replace with your agent pool name
$AzpToken="3dA3vvdXptOiGSPHcP7vuVKvlODR2jN7NUinfE2MZNm5qNCWCVxFJQQJ99BBACAAAAAFfy4cAAASAZDOcTxP" # replace with your PAT
$OrganizationUrl="https://dev.azure.com/ProgrammingWithWolfgang" # replace with your ADO URL
```

## Create the Storage Account and FIle Share

```
az group create --name "$ResourceGroup" --location "$Location"

az storage account create `
    --resource-group $ResourceGroup `
    --name $StorageAccountName `
    --location "$Location" `
    --kind StorageV2 `
    --sku Standard_LRS `
    --enable-large-file-share `
    --query provisioningState

az storage share-rm create `
    --resource-group $ResourceGroup `
    --storage-account $StorageAccountName `
    --name $StorageShareName `
    --quota 32 `
    --enabled-protocols SMB `
    --output table

$StorageAccountKey=$(`
    az storage account keys list `
    --account-name $StorageAccountName `
    --query "[0].value" `
    --output tsv)
```

# Create the Container App

```
az containerapp env create `
    --name "$Environment" `
    --resource-group "$ResourceGroup" `
    --location "$Location"

az containerapp env storage set `
    --access-mode ReadWrite `
    --azure-file-account-name $StorageAccountName `
    --azure-file-account-key $StorageAccountKey `
    --azure-file-share-name $StorageShareName `
    --storage-name $StorageMountName `
    --name $Environment `
    --resource-group $ResourceGroup `
    --output table

az containerapp create `
    --name "$ContainerAppName" `
    --resource-group "$ResourceGroup" `
    --environment "$Environment" `
    --image "$ContainerImageName" `
    --cpu "0.25" `
    --memory "0.5Gi" `
    --secrets "personal-access-token=$AzpToken" `
    --env-vars "AZP_TOKEN=secretref:personal-access-token" "AZP_URL=$OrganizationUrl" "AZP_POOL=$AzpPool" "AZP_AGENT_NAME=agent" 

az containerapp show `
    --name $ContainerAppName `
    --resource-group $ResourceGroup `
    --output yaml > DeployedContainerApp.yaml
```

Add the volumes and volumeMounts sections to the previously downloaded yaml file

```
  template:
    volumes:
    - name: azure-file-volume
      storageName: adoagentstoragemount
      storageType: AzureFile
    containers:
    - env:
      - name: AZP_TOKEN
        secretRef: personal-access-token
      - name: AZP_URL
        secretRef: https://dev.azure.com/ProgrammingWithWolfgang
      - name: AZP_POOL
        value: Keda
      image: wolfgangofner/adoagentkeda
      name: azure-pipelines-agent-job
      volumeMounts:
      - volumeName: azure-file-volume
        mountPath: /share
      resources:
        cpu: 2.0
        ephemeralStorage: ''
        memory: 4Gi
    initContainers: null
  workloadProfileName: Consumption

az containerapp update `
    --name $ContainerAppName `
    --resource-group $ResourceGroup `
    --yaml DeployedContainerApp.yaml `
    --output table

az containerapp delete `
    --resource-group $ResourceGroup `
    --name $ContainerAppName `
    --yes

az containerapp env delete `
    --name "$Environment" `
    --resource-group "$ResourceGroup" `
    --yes
```

## Better Approach to attach the Storage Volume

```
az containerapp env create `
    --name "$Environment" `
    --resource-group "$ResourceGroup" `
    --location "$Location"

az containerapp env storage set `
    --access-mode ReadWrite `
    --azure-file-account-name $StorageAccountName `
    --azure-file-account-key $StorageAccountKey `
    --azure-file-share-name $StorageShareName `
    --storage-name $StorageMountName `
    --name $Environment `
    --resource-group $ResourceGroup `
    --output table

az containerapp create `
    --name "$ContainerAppName" `
    --resource-group "$ResourceGroup" `
    --environment "$Environment" `
    --yaml ContainerApp.yaml
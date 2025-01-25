## Prepare Azure DevOps Server

- Create PAT
- Create self-hosted Agent Pool

## Define Variables
```
$ResourceGroup="devops-agent-container-apps"
$Location="canadacentral" # replace with a location close to you
$Environment="devops-agent-env"
$JobName="azure-pipelines-agent-job"
$PlaceholderJobName="placeholder-agent-job"
$AzpToken="<PERSONAL_ACCESS_TOKEN>" # replace with your PAT
$AzpPool="AgentInContainer" # replace with your agent pool name
$OrganizationUrl="https://dev.azure.com/<DEVOPS_URL>" # replace with your ADO URL
$ContainerImageName="adoagent" # replace with your agent name (or leave as is to use mine)
$ContainerRegistry="wolfgangofner" # replace with your agent name (or leave as is to use mine)
$StorageAccountName="<STORAGE_ACCOUNT_NAME>" # name must be unique world wide
$StorageShareName="adoagentfileshare"
$StorageMountName="adoagentstoragemount"
```

## Test locally

```
docker run -e AZP_URL=$OrganizationUrl -e AZP_TOKEN=$AzpToken -e AZP_AGENT_NAME=agent -e AZP_POOL=$AzpPool $ContainerRegistry/$ContainerImageName
```

## Deploy Placeholder

```
az group create --name "$ResourceGroup" --location "$Location"

az containerapp env create --name "$Environment" --resource-group "$ResourceGroup" --location "$Location"

az containerapp job create `
    --name "$PlaceholderJobName" `
    --resource-group "$ResourceGroup" `
    --environment "$Environment" `
    --image "$ContainerRegistry/$ContainerImageName" `
    --cpu "0.25" `
    --memory "0.5Gi" `
    --secrets "personal-access-token=$AzpToken" "organization-url=$OrganizationUrl" `
    --env-vars "AZP_TOKEN=secretref:personal-access-token" "AZP_URL=secretref:organization-url" "AZP_POOL=$AzpPool" "AZP_PLACEHOLDER=1" "AZP_AGENT_NAME=placeholder-agent" `
    --trigger-type Manual `
    --replica-timeout 300 `
    --replica-retry-limit 0 `
    --replica-completion-count 1 `
    --parallelism 1

az containerapp job start --name "$PlaceholderJobName" --resource-group "$ResourceGroup"

az containerapp job execution list `
    --name "$PlaceholderJobName" `
    --resource-group "$ResourceGroup" `
    --output table `
    --query '[].{Status: properties.status, Name: name, StartTime: properties.startTime}'
```

## Test Container Job

- Run pipeline using previously created Agent Pool
- Disable agent in Agent Pool

## Create Container App and scale with KEDA

```
az containerapp job create --name "$JobName" --resource-group "$ResourceGroup" --environment "$Environment" `
    --trigger-type Event `
    --replica-timeout 1800 `
    --replica-retry-limit 0 `
    --replica-completion-count 1 `
    --parallelism 1 `
    --image "$ContainerRegistry/$ContainerImageName" `
    --min-executions 0 `
    --max-executions 10 `
    --polling-interval 30 `
    --scale-rule-name "azure-pipelines" `
    --scale-rule-type "azure-pipelines" `
    --scale-rule-metadata "poolName=$AzpPool" "targetPipelinesQueueLength=1" `
    --scale-rule-auth "personalAccessToken=personal-access-token" "organizationURL=organization-url" `
    --cpu "2.0" `
    --memory "4Gi" `
    --secrets "personal-access-token=$AzpToken" "organization-url=$OrganizationUrl" `
    --env-vars "AZP_TOKEN=secretref:personal-access-token" "AZP_URL=secretref:organization-url" "AZP_POOL=$AzpPool" 
```

## Attach Volume to Container App

### Create Storage Account

```
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

$StorageAccountKey=$(az storage account keys list --account-name $StorageAccountName --query "[0].value" -o tsv)
```

### Update Container App

```
az containerapp env storage set `
    --name $Environment `
    --resource-group $ResourceGroup `
    --access-mode ReadWrite `
    --azure-file-account-name $StorageAccountName `
    --azure-file-account-key $StorageAccountKey `
    --azure-file-share-name $StorageShareName `
    --storage-name $StorageMountName `
    --output table

az containerapp job show `
    --name $JobName `
    --resource-group $ResourceGroup `
    --output yaml > DeployedContainerApp.yaml

az containerapp job update `
    --name $JobName `
    --resource-group $ResourceGroup `
    --yaml ContainerApp.yaml `
    --output table
```
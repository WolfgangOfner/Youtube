## Define Variables
```powershell
$ResourceGroup="app-insights-mi-rg"
$Location="canadacentral"

$AppServicePlan="demo-mi-plan"
$WebAppName="app-insights-mi-wolfgang-app"   # must be globally unique
$LogAnalyticsWorkspace="demo-mi-law"
$AppInsightsName="demo-mi-appi"

$ContainerAppsEnv="demo-mi-cae"
$ContainerAppName="demo-mi-ca"
$ContainerImage="docker.io/wolfgangofner/containerapp-mi-law:latest"

$VNetName="app-insights-mi-vnet"
$VNetAddressPrefix="10.10.0.0/16"
$AppServiceSubnetName="app-insights-mi-app-snet"
$AppServiceSubnetPrefix="10.10.1.0/24"
$ContainerAppsSubnetName="app-insights-mi-aca-snet"
$ContainerAppsSubnetPrefix="10.10.2.0/23"   # /23 minimum for Container Apps workload profiles
$PrivateEndpointSubnetName="app-insights-mi-pe-snet"
$PrivateEndpointSubnetPrefix="10.10.4.0/24"

# AMPLS = Azure Monitor Private Link Scope
$AmplsName="app-insights-mi-ampls"
$PrivateEndpointName="app-insights-mi-ampls-pe"

$VmSubnetName="app-insights-mi-vm-snet"
$VmSubnetPrefix="10.10.5.0/24"
$VmNsgName="app-insights-mi-nsg"
$VmName="appi-mi-vm"
$VmAdminUsername="wolfgang"
```

## Create Resource Group and Virtual Network
```powershell
az group create `
  --name $ResourceGroup `
  --location $Location

az network vnet create `
  --resource-group $ResourceGroup `
  --name $VNetName `
  --location $Location `
  --address-prefix $VNetAddressPrefix `
  --subnet-name $AppServiceSubnetName `
  --subnet-prefix $AppServiceSubnetPrefix

az network vnet subnet update `
  --resource-group $ResourceGroup `
  --vnet-name $VNetName `
  --name $AppServiceSubnetName `
  --delegations Microsoft.Web/serverFarms

az network vnet subnet create `
  --resource-group $ResourceGroup `
  --vnet-name $VNetName `
  --name $ContainerAppsSubnetName `
  --address-prefix $ContainerAppsSubnetPrefix

az network vnet subnet update `
  --resource-group $ResourceGroup `
  --vnet-name $VNetName `
  --name $ContainerAppsSubnetName `
  --delegations Microsoft.App/environments

az network vnet subnet create `
  --resource-group $ResourceGroup `
  --vnet-name $VNetName `
  --name $PrivateEndpointSubnetName `
  --address-prefix $PrivateEndpointSubnetPrefix `
  --private-endpoint-network-policies Disabled

$ContainerAppsSubnetId=az network vnet subnet show `
  --resource-group $ResourceGroup `
  --vnet-name $VNetName `
  --name $ContainerAppsSubnetName `
  --query id -o tsv
```

## Create Private DNS Zones for Azure Monitor Private Link
```powershell
# OMS = Operations Management Suite, ODS = Operations Data Service
$PrivateDnsZones = @(
  "privatelink.monitor.azure.com",
  "privatelink.oms.opinsights.azure.com",
  "privatelink.ods.opinsights.azure.com"
)

foreach ($zone in $PrivateDnsZones) {
  az network private-dns zone create `
    --resource-group $ResourceGroup `
    --name $zone

  az network private-dns link vnet create `
    --resource-group $ResourceGroup `
    --zone-name $zone `
    --name "link-$($zone -replace '\.', '-')" `
    --virtual-network $VNetName `
    --registration-enabled false
}
```

## Create App Service and App Insights
```powershell
az monitor log-analytics workspace create `
  --resource-group $ResourceGroup `
  --workspace-name $LogAnalyticsWorkspace `
  --location $Location

$LawId=az monitor log-analytics workspace show `
  --resource-group $ResourceGroup `
  --workspace-name $LogAnalyticsWorkspace `
  --query id -o tsv

az monitor app-insights component create `
  --app $AppInsightsName `
  --location $Location `
  --resource-group $ResourceGroup `
  --workspace $LawId `
  --kind web

$AppiId=az monitor app-insights component show `
  --app $AppInsightsName `
  --resource-group $ResourceGroup `
  --query id -o tsv

$ConnectionString=az monitor app-insights component show `
  --app $AppInsightsName `
  --resource-group $ResourceGroup `
  --query connectionString -o tsv

az resource update `
  --ids $AppiId `
  --set properties.DisableLocalAuth=true

# Connect App Insights and Log Analytics to an Azure Monitor Private Link Scope
az monitor private-link-scope create `
  --resource-group $ResourceGroup `
  --name $AmplsName

az monitor private-link-scope scoped-resource create `
  --resource-group $ResourceGroup `
  --scope-name $AmplsName `
  --name "law-connection" `
  --linked-resource $LawId

az monitor private-link-scope scoped-resource create `
  --resource-group $ResourceGroup `
  --scope-name $AmplsName `
  --name "appi-connection" `
  --linked-resource $AppiId

$AmplsId=az monitor private-link-scope show `
  --resource-group $ResourceGroup `
  --name $AmplsName `
  --query id -o tsv

az network private-endpoint create `
  --resource-group $ResourceGroup `
  --name $PrivateEndpointName `
  --vnet-name $VNetName `
  --subnet $PrivateEndpointSubnetName `
  --private-connection-resource-id $AmplsId `
  --group-id azuremonitor `
  --connection-name "pe-connection-ampls"

az network private-endpoint dns-zone-group create `
  --resource-group $ResourceGroup `
  --endpoint-name $PrivateEndpointName `
  --name "ampls-dns-zone-group" `
  --private-dns-zone "privatelink.monitor.azure.com" `
  --zone-name "monitor"

az network private-endpoint dns-zone-group add `
  --resource-group $ResourceGroup `
  --endpoint-name $PrivateEndpointName `
  --name "ampls-dns-zone-group" `
  --private-dns-zone "privatelink.oms.opinsights.azure.com" `
  --zone-name "oms"

az network private-endpoint dns-zone-group add `
  --resource-group $ResourceGroup `
  --endpoint-name $PrivateEndpointName `
  --name "ampls-dns-zone-group" `
  --private-dns-zone "privatelink.ods.opinsights.azure.com" `
  --zone-name "ods"

az resource update `
  --ids $AmplsId `
  --set properties.accessModeSettings.ingestionAccessMode=PrivateOnly properties.accessModeSettings.queryAccessMode=PrivateOnly

az resource update `
  --ids $LawId `
  --set properties.publicNetworkAccessForIngestion=Disabled properties.publicNetworkAccessForQuery=Disabled

az resource update `
  --ids $AppiId `
  --set properties.publicNetworkAccessForIngestion=Disabled properties.publicNetworkAccessForQuery=Disabled

az appservice plan create `
  --name $AppServicePlan `
  --resource-group $ResourceGroup `
  --sku B1

az webapp create `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --plan $AppServicePlan `
  --runtime '"dotnet|10"' `
  --deployment-source-url "https://github.com/Azure-Samples/dotnetcore-docs-hello-world" `
  --deployment-source-branch "master"

az webapp vnet-integration add `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --vnet $VNetName `
  --subnet $AppServiceSubnetName

az webapp config set `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --vnet-route-all-enabled true

$PrincipalId=az webapp identity assign `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --query principalId -o tsv

az role assignment create `
  --assignee-object-id $PrincipalId `
  --assignee-principal-type ServicePrincipal `
  --role "Monitoring Metrics Publisher" `
  --scope $AppiId

az webapp config appsettings set `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --settings `
    APPLICATIONINSIGHTS_CONNECTION_STRING=$ConnectionString `
    APPLICATIONINSIGHTS_AUTHENTICATION_STRING="Authorization=AAD" `
    ApplicationInsightsAgent_EXTENSION_VERSION="~3"

Write-Host "Done. Web App: https://$WebAppName.azurewebsites.net"

while ($true) {
  $requestCount = Get-Random -Minimum 1 -Maximum 21   # 1-20 requests this second
  1..$requestCount | ForEach-Object {
    try {
      Invoke-WebRequest -Uri "https://$WebAppName.azurewebsites.net" -UseBasicParsing | Out-Null
    } catch {
      Write-Host "$(Get-Date -Format 'HH:mm:ss') - request failed: $_"
    }
  }
  Write-Host "$(Get-Date -Format 'HH:mm:ss') - sent $requestCount requests"
  Start-Sleep -Seconds 1
}
```

## Create Container App
```powershell
az containerapp env create `
  --name $ContainerAppsEnv `
  --resource-group $ResourceGroup `
  --location $Location `
  --logs-destination azure-monitor `
  --infrastructure-subnet-resource-id $ContainerAppsSubnetId

$ContainerAppsEnvId=az containerapp env show `
  --name $ContainerAppsEnv `
  --resource-group $ResourceGroup `
  --query id -o tsv

az monitor diagnostic-settings create `
  --name "diag-$ContainerAppsEnv" `
  --resource $ContainerAppsEnvId `
  --workspace $LawId `
  --logs '[{"category":"ContainerAppConsoleLogs","enabled":true},{"category":"ContainerAppSystemLogs","enabled":true}]'

az containerapp create `
  --name $ContainerAppName `
  --resource-group $ResourceGroup `
  --environment $ContainerAppsEnv `
  --image $ContainerImage `
  --target-port 8080 `
  --ingress external

az containerapp identity assign `
  --name $ContainerAppName `
  --resource-group $ResourceGroup `
  --system-assigned

$ContainerAppPrincipalId=az containerapp show `
  --name $ContainerAppName `
  --resource-group $ResourceGroup `
  --query identity.principalId -o tsv

az role assignment create `
  --assignee-object-id $ContainerAppPrincipalId `
  --assignee-principal-type ServicePrincipal `
  --role "Monitoring Metrics Publisher" `
  --scope $AppiId

az containerapp update `
  --name $ContainerAppName `
  --resource-group $ResourceGroup `
  --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=$ConnectionString" "APPLICATIONINSIGHTS_AUTHENTICATION_STRING=Authorization=AAD" "APPLICATIONINSIGHTS_ROLE_NAME=$ContainerAppName"

$ContainerAppUrl=az containerapp show `
  --name $ContainerAppName `
  --resource-group $ResourceGroup `
  --query properties.configuration.ingress.fqdn -o tsv

Write-Host "Done. Container App: https://$ContainerAppUrl"

while ($true) {
  try {
    Invoke-WebRequest -Uri "https://$ContainerAppUrl" -UseBasicParsing | Out-Null
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - request sent"
  } catch {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - request failed: $_"
  }
  Start-Sleep -Seconds 1
}
```

## Verifying the data in Log Analytics
```powershell
az resource update `
  --ids $LawId `
  --set properties.publicNetworkAccessForQuery=Enabled

az resource update `
  --ids $AppiId `
  --set properties.publicNetworkAccessForQuery=Enabled
```

```powershell
$result = az monitor app-insights query `
  --apps $AppInsightsName `
  --resource-group $ResourceGroup `
  --analytics-query "requests | where timestamp > ago(10h) | project timestamp, name, cloud_RoleName, resultCode | order by timestamp desc | take 20" `
  -o json | ConvertFrom-Json

$columns = $result.tables[0].columns.name
$result.tables[0].rows | ForEach-Object {
  $row = $_
  $obj = [ordered]@{}
  for ($i = 0; $i -lt $columns.Count; $i++) { $obj[$columns[$i]] = $row[$i] }
  [pscustomobject]$obj
} | Format-Table -AutoSize
```

```kusto
union requests, traces, exceptions, dependencies
| where timestamp > ago(10h)
| project timestamp, itemType, name, cloud_RoleName, resultCode
| order by timestamp desc
```

```powershell

az resource update `
  --ids $LawId `
  --set properties.publicNetworkAccessForQuery=Disabled

az resource update `
  --ids $AppiId `
  --set properties.publicNetworkAccessForQuery=Disabled
```

## Create a VM to Test Private-Only Access
```powershell
az network nsg create `
  --resource-group $ResourceGroup `
  --name $VmNsgName

az network nsg rule create `
  --resource-group $ResourceGroup `
  --nsg-name $VmNsgName `
  --name "AllowRdpFromMyIp" `
  --priority 100 `
  --direction Inbound `
  --access Allow `
  --protocol Tcp `
  --source-address-prefixes "*" `
  --source-port-ranges '*' `
  --destination-port-ranges 3389

az network vnet subnet create `
  --resource-group $ResourceGroup `
  --vnet-name $VNetName `
  --name $VmSubnetName `
  --address-prefix $VmSubnetPrefix `
  --network-security-group $VmNsgName

$VmAdminPassword = Read-Host -Prompt "Enter a password for the VM admin account" -AsSecureString
$VmAdminPasswordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($VmAdminPassword))

az vm create `
  --resource-group $ResourceGroup `
  --name $VmName `
  --image "MicrosoftWindowsDesktop:windows-11:win11-25h2-pro:latest" `
  --vnet-name $VNetName `
  --subnet $VmSubnetName `
  --public-ip-sku Standard `
  --size Standard_D4s_v5 `
  --admin-username $VmAdminUsername `
  --admin-password $VmAdminPasswordPlain `
  --security-type TrustedLaunch `
  --enable-secure-boot true `
  --enable-vtpm true

$VmPublicIp = az vm show `
  --resource-group $ResourceGroup `
  --name $VmName `
  --show-details `
  --query publicIps -o tsv

mstsc /v:$VmPublicIp
```
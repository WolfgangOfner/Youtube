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
```

## Create App Service and App Insights
```powershell
az group create `
  --name $ResourceGroup `
  --location $Location

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
  --logs-destination azure-monitor

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

### Building the image yourself (optional)

Only needed if you want your own copy instead of `wolfgangofner/containerapp-mi-law`. Container Apps runs `linux/amd64`, so force the platform if building on an ARM machine:
```powershell
docker build --platform linux/amd64 -t <your-dockerhub-user>/containerapp-mi-law:latest .
docker push <your-dockerhub-user>/containerapp-mi-law:latest

docker build --platform linux/amd64 -t wolfgangofner/containerapp-mi-law:latest .
wolfgangofner/containerapp-mi-law:latest
```

## Verifying the data in Log Analytics

```powershell
$result = az monitor app-insights query `
  --apps $AppInsightsName `
  --resource-group $ResourceGroup `
  --analytics-query "requests | where timestamp > ago(1h) | project timestamp, name, cloud_RoleName, resultCode | order by timestamp desc | take 20" `
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
| where timestamp > ago(1h)
| project timestamp, itemType, name, cloud_RoleName, resultCode
| order by timestamp desc
```
## Define Variables
```
$AppServiceName="my-secure-app-wolfgang"
$Location="CanadaCentral"
$ResourceGroupName="app-service-authentication-rg"
```

## Create App Registration
```
Secure App Service App Registration
my-secure-app-wolfgang.azurewebsites.net
https://my-secure-app-wolfgang.azurewebsites.net/.auth/login/aad/callback
```

## Create App Service
```
az group create `
  --name $ResourceGroupName `
  --location $Location

az deployment group create `
  --resource-group $ResourceGroupName `
  --template-file "main.bicep" `
  --parameters webAppName="$AppServiceName" `
  --parameters entraClientId="XXX"
```

## Federated Credentials
```
Secure-App-Federated-Credentials
user_impersonation
```
param webAppName string = 'my-secure-app'
param location string = resourceGroup().location

@description('The Application (client) ID from the Entra ID App Registration')
param entraClientId string

param tenantId string = subscription().tenantId

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${webAppName}-identity'
  location: location
}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${webAppName}-plan'
  location: location
  sku: {
    name: 'P1v3'
  }
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|8.0'
      appSettings: [
        {
          name: 'WEBSITE_AUTH_AAD_ALLOWED_TENANTS'
          value: tenantId
        }
      ]
    }
  }
}

resource webAppAuth 'Microsoft.Web/sites/config@2023-01-01' = {
  parent: webApp
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'AzureActiveDirectory'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          openIdIssuer: '${environment().authentication.loginEndpoint}${tenantId}/v2.0'
          clientId: entraClientId
          #disable-next-line BCP037
          clientSecretManagedIdentityResourceId: managedIdentity.id
        }
        validation: {
          allowedAudiences: [
            'api://${entraClientId}'
            'https://${webApp.properties.defaultHostName}'
          ]
        }
      }
    }
    login: {
      tokenStore: {
        enabled: true
      }
    }
  }
}

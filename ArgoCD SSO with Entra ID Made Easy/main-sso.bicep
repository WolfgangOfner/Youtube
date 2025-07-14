var clusterName = 'argocd-aks'
var ssoWorkloadIdentityClientId = '024fce46-211d-43c0-8e19-636241c42384'
var url = 'https://130.107.184.95/'
var oidcConfig = '''
name: Azure
issuer: https://login.microsoftonline.com/6954bb4d-a0f5-4084-b434-5d10af03058e/v2.0
clientID: 024fce46-211d-43c0-8e19-636241c42384
azure:
  useWorkloadIdentity: true
requestedIDTokenClaims:
  groups:
    essential: true
requestedScopes:
  - openid
  - profile
  - email
'''

var defaultPolicy = 'role:readonly'
var policy = '''
p, role:org-admin, applications, *, */*, allow
p, role:org-admin, clusters, get, *, allow
p, role:org-admin, repositories, get, *, allow
p, role:org-admin, repositories, create, *, allow
p, role:org-admin, repositories, update, *, allow
p, role:org-admin, repositories, delete, *, allow
g, demo.user@programmingwithwolfgang.com, role:org-admin
'''

resource cluster 'Microsoft.ContainerService/managedClusters@2024-10-01' existing = {
  name: clusterName
}

resource extension 'Microsoft.KubernetesConfiguration/extensions@2023-05-01' = {
  name: 'argocd'
  scope: cluster
  properties: {
    extensionType: 'Microsoft.ArgoCD'
    autoUpgradeMinorVersion: false
    releaseTrain: 'preview'
    version: '0.0.7-preview'
    configurationSettings: {
      'workloadIdentity.enable': 'true'
      'workloadIdentity.entraSSOClientId': ssoWorkloadIdentityClientId  
      'config-maps.argocd-cm.data.oidc\\.config': oidcConfig   
      'config-maps.argocd-cm.data.url': url   
      'config-maps.argocd-rbac-cm.data.policy\\.default': defaultPolicy
      'config-maps.argocd-rbac-cm.data.policy\\.csv': policy
      'config-maps.argocd-rbac-cm.data.scopes': '[groups, email]'
    }
  }
}

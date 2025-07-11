var clusterName = 'argocd-aks'

var workloadIdentityClientId = 'XXX'

var defaultPolicy = 'role:readonly'
var policy = '''
p, role:org-admin, applications, *, */*, allow
p, role:org-admin, clusters, get, *, allow
p, role:org-admin, repositories, get, *, allow
p, role:org-admin, repositories, create, *, allow
p, role:org-admin, repositories, update, *, allow
p, role:org-admin, repositories, delete, *, allow
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
      'workloadIdentity.clientId': workloadIdentityClientId
      'config-maps.argocd-rbac-cm.data.policy\\.default': defaultPolicy
      'config-maps.argocd-rbac-cm.data.policy\\.csv': policy
      deployWithHighAvailability: 'false'
    }
  }
}
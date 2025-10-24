## Define Variables
```
$InfrastructureNamespace="alb-infra"
$GatewayName="gateway"
$ClusterIssuerName="letsencrypt-prod"
$ApplicationLoadBalancerName="application-load-balancer"
$GatewayClassName="azure-alb-external"

$TraefikSecretName="traefik-letsencrypt-secret"
$TraefikUrl="traefik.programmingwithwolfgang.com"
$NginxSecretName="nginx-letsencrypt-secret"
$NginxUrl="nginx.programmingwithwolfgang.com"

$AksName="app-gateway-container-aks"
$ResourceGroupName="app-gateway-container-rg"
$DnsZoneName="programmingwithwolfgang.com"
$DnsSubscriptionName="ProgrammingWithWolfgang"
$DnsSubscriptionId=$(az account show --subscription "$DnsSubscriptionName" --query id --output tsv)
$DnsResourceGroup="ProgrammingWithWolfgang"

$Namespace="wildcard"
$PrSecretName="pr-letsencrypt-secret"
$PrCertificateName="pr-letsencrypt-cert"
$Domain="pullrequest.programmingwithwolfgang.com"
$CertManagerManagedIdentityName="cert-manager"
$CertManagerServiceAccountName="cert-manager"
$CertManagerNamespace="cert-manager"
```

## Use Entra Workload Identity on the Cert Manager
Helm upgrade because the cert-manager was installed in the last video. If you don't have a cert-manager yet, use helm install

https://cert-manager.io/docs/configuration/acme/dns01/azuredns/
```
helm repo add jetstack https://charts.jetstack.io --force-update

helm upgrade cert-manager jetstack/cert-manager `
  --namespace $CertManagerNamespace `
  --create-namespace `
  --version v1.17.1 `
  --set config.enableGatewayAPI=true `
  --set crds.enabled=true `
  --set-string podLabels."azure\.workload\.identity/use"=true `
  --set-string serviceAccount.labels."azure\.workload\.identity/use"=true

kubectl describe pod -n cert-manager -l app.kubernetes.io/component=controller

az identity create `
  --name $CertManagerManagedIdentityName `
  --resource-group $ResourceGroupName

$CertManagerManagedIdentityClientId=$(`
  az identity show `
  --name $CertManagerManagedIdentityName `
  --resource-group $ResourceGroupName `
  --query 'clientId' `
  --output tsv)

az role assignment create `
    --role "DNS Zone Contributor" `
    --assignee $CertManagerManagedIdentityClientId `
    --scope $(`
        az network dns zone show `
        --name $DnsZoneName `
        --resource-group $DnsResourceGroup `
        --subscription $DnsSubscriptionName `
        --query id `
        --output tsv )

$AksOidcIssuer="$(`
  az aks show `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --query "oidcIssuerProfile.issuerUrl" `
  --output tsv)"

az identity federated-credential create `
  --name "cert-manager" `
  --identity-name $CertManagerManagedIdentityName `
  --resource-group $ResourceGroupName `
  --issuer $AksOidcIssuer `
  --subject "system:serviceaccount:${CertManagerNamespace}:${CertManagerServiceAccountName}"
```

## Update the Cluster Issuer to access the DNS-Zone
```

$ClusterIssuer = @"
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: $ClusterIssuerName
  namespace: $InfrastructureNamespace
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory # production endpoint
    # server: https://acme-staging-v02.api.letsencrypt.org/directory # staging endpoint
    email: wolfgang@prorgrammingwithwolfgang.com # your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-private-key
    solvers:
      - http01:
          gatewayHTTPRoute:
            parentRefs:
              - name: $GatewayName
                namespace: $InfrastructureNamespace
                kind: Gateway
      - dns01:
          azureDNS:
            hostedZoneName: $DnsZoneName
            resourceGroupName: $DnsResourceGroup
            subscriptionID: $DnsSubscriptionId
            environment: AzurePublicCloud
            managedIdentity:
              clientID: $CertManagerManagedIdentityClientId
"@

$ClusterIssuer | kubectl apply -f -

kubectl get ClusterIssuer -A -o yaml
```

## Create a Test Application to test the Wildcard Certificate
```

kubectl create ns $Namespace

$App = @"
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: "whoami-deployment"
     labels:
       app: whoami
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: whoami
     template:
       metadata:
         labels:
           app: whoami
       spec:
         containers:
         - name: whoami
           image: traefik/whoami:latest
           ports:
           - containerPort: 80
"@

$App | kubectl apply -f - -n $Namespace

$Service = @"
apiVersion: v1
kind: Service
metadata:
  name: whoami
  labels:
    app: whoami
spec:
  type: ClusterIP
  selector:
    app: whoami
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
"@

$Service | kubectl apply -f - -n $Namespace
```

## Create a Wild Card Certificate and update the Gateway Listeners
```
$Certificate = @"
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: $PrCertificateName
  namespace: $InfrastructureNamespace
spec:
  secretName: $PrSecretName
  issuerRef:
    name: $ClusterIssuerName
    kind: ClusterIssuer
  dnsNames:
    - "*.$Domain"
"@

$Certificate | kubectl apply -f -

kubectl get certificate $PrCertificateName -n $InfrastructureNamespace
kubectl get challenges -n $InfrastructureNamespace -o yaml

$Gateway = @"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: $GatewayName
  namespace: $InfrastructureNamespace
  annotations:
    alb.networking.azure.io/alb-namespace: $InfrastructureNamespace
    alb.networking.azure.io/alb-name: $ApplicationLoadBalancerName
    cert-manager.io/cluster-issuer: $ClusterIssuerName
spec:
  gatewayClassName: $GatewayClassName
  listeners:
  - name: http-listener
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
  - name: traefik-https-listener
    port: 443
    protocol: HTTPS
    hostname: $TraefikUrl
    tls:
      certificateRefs:
        - group: ""
          kind: Secret
          name: $TraefikSecretName
          namespace: $InfrastructureNamespace   
    allowedRoutes:
      namespaces:
        from: All
  - name: nginx-https-listener
    port: 443
    protocol: HTTPS
    hostname: $NginxUrl
    tls:
      certificateRefs:
        - group: ""
          kind: Secret
          name: $NginxSecretName
          namespace: $InfrastructureNamespace    
    allowedRoutes:
      namespaces:
        from: All
  - name: pr-https-listener
    port: 443
    protocol: HTTPS
    hostname: "*.$Domain"
    tls:
      certificateRefs:
        - group: ""
          kind: Secret
          name: $PrSecretName
          namespace: $InfrastructureNamespace    
    allowedRoutes:
      namespaces:
        from: All
"@

$Gateway | kubectl apply -f -

kubectl get gateway $GatewayName -n $InfrastructureNamespace -o yaml
```

## Create HttpRoute and test Certificate
```

$HttpRoute = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: pr-httproute
  namespace: $Namespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $InfrastructureNamespace
  hostnames:
    - pr-2.$Domain
  rules:
    - matches:
      backendRefs:
        - name: whoami
          port: 80
"@

$HttpRoute | kubectl apply -f -

kubectl get httproute pr-httproute -n $Namespace -o yaml
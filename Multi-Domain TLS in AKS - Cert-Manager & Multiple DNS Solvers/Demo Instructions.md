## Define Variables
```
$AksName="cert-manager-multi-dns-aks"
$Location="CanadaCentral"
$ResourceGroupName="cert-manager-multi-dns-rg"

$GatewayNamespace="gateway"
$GatewayName="gateway"
$GatewayClassName="envoy"

$DnsZoneName="programmingwithwolfgang.com"
$DnsSubscriptionName="ProgrammingWithWolfgang"
$DnsSubscriptionId=$(az account show --subscription "$DnsSubscriptionName" --query id --output tsv)
$DnsSubZoneOne="subzone.$DnsZoneName"
$DnsSubZoneTwo="another.$DnsZoneName"
$DnsResourceGroup="ProgrammingWithWolfgang"


$CertManagerManagedIdentityName="cert-manager"
$CertManagerServiceAccountName="cert-manager"
$CertManagerNamespace="cert-manager"
$ClusterIssuerName="letsencrypt"

$DemoOneNamespace="demo-one-ns"
$DemoOneHttpRoute="demo-one-http-route"
$DemoOneAppName="demoapp-one"
$DemoTwoNamespace="demo-two-ns"
$DemoTwoHttpRoute="demo-two-http-route"
$DemoTwoAppName="demoapp-two"
```

## Create AKS
```
az group create `
  --name $ResourceGroupName `
  --location $Location

az aks create `
  --name $AksName `
  --resource-group $ResourceGroupName `
  --enable-oidc-issuer `
  --enable-workload-identity `

az aks get-credentials `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --overwrite-existing
```

## Deploy Envoy and create the Gateway and GatewayClass
```
helm install envoy oci://docker.io/envoyproxy/gateway-helm `
  --version v1.7.2 `
  --namespace $GatewayNamespace `
  --create-namespace

$GatewayClass = @"
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: $GatewayClassName
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
"@

$GatewayClass | kubectl apply -f -

$Gateway = @"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: $GatewayName
  namespace: $GatewayNamespace
  annotations:
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
  - name: sub-https-listener
    port: 443
    protocol: HTTPS
    hostname: $DnsSubZoneOne
    allowedRoutes:
      namespaces:
        from: All 
    tls:
      certificateRefs:
        - group: ""
          kind: Secret
          name: sub-secret
  - name: another-https-listener
    port: 443
    protocol: HTTPS
    hostname: $DnsSubZoneTwo
    allowedRoutes:
      namespaces:
        from: All 
    tls:
      certificateRefs:
        - group: ""
          kind: Secret
          name: another-secret
"@

$Gateway | kubectl apply -f -

kubectl get gateway -n $GatewayNamespace 
```

might take a minute to switch Programmed = True

```
kubectl get gatewayclass

kubectl get gateway $GatewayName -n $GatewayNamespace -o jsonpath='{.status.addresses[0].value}'
```

Update DNS in Portal

## Use Entra Workload Identity on the Cert Manager
```
helm repo add jetstack https://charts.jetstack.io --force-update

helm install cert-manager jetstack/cert-manager `
  --namespace $CertManagerNamespace `
  --create-namespace `
  --version v1.20.2 `
  --set config.enableGatewayAPI=true `
  --set crds.enabled=true `
  --set-string podLabels."azure\.workload\.identity/use"=true `
  --set-string serviceAccount.labels."azure\.workload\.identity/use"=true

$CertManagerManagedIdentityClientId=$(`
  az identity create `
  --name $CertManagerManagedIdentityName `
  --resource-group $ResourceGroupName `
  --query 'clientId' `
  --output tsv)

az role assignment create `
    --role "DNS Zone Contributor" `
    --assignee $CertManagerManagedIdentityClientId `
    --scope $(`
        az network dns zone show `
        --name $DnsSubZoneOne `
        --resource-group $DnsResourceGroup `
        --subscription $DnsSubscriptionName `
        --query id `
        --output tsv)

az role assignment create `
    --role "DNS Zone Contributor" `
    --assignee $CertManagerManagedIdentityClientId `
    --scope $(`
        az network dns zone show `
        --name $DnsSubZoneTwo `
        --resource-group $DnsResourceGroup `
        --subscription $DnsSubscriptionName `
        --query id `
        --output tsv)

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

## Create the ClusterIssuer and configure Access the DNS-Zone
```
$ClusterIssuer = @"
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: $ClusterIssuerName
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    # server: https://acme-staging-v02.api.letsencrypt.org/directory # staging endpoint
    email: your@email.com
    privateKeySecretRef:
      name: letsencrypt-private-key
    solvers:
      - selector:
          dnsZones:
            - "$DnsSubZoneOne"
        dns01:
          azureDNS:
            hostedZoneName: $DnsSubZoneOne
            resourceGroupName: $DnsResourceGroup
            subscriptionID: $DnsSubscriptionId
            environment: AzurePublicCloud
            managedIdentity:
              clientID: $CertManagerManagedIdentityClientId
      - selector:
          dnsZones:
            - "$DnsSubZoneTwo"
        dns01:
          azureDNS:
            hostedZoneName: $DnsSubZoneTwo
            resourceGroupName: $DnsResourceGroup
            subscriptionID: $DnsSubscriptionId
            environment: AzurePublicCloud
            managedIdentity:
              clientID: $CertManagerManagedIdentityClientId
"@

$ClusterIssuer | kubectl apply -f -

kubectl get ClusterIssuer -o yaml
```

## Deploy first Test App
```
$DemoOneDeployment = @"
apiVersion: v1
kind: Namespace
metadata:
  name: $DemoOneNamespace
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${DemoOneAppName}-deployment"
  namespace: $DemoOneNamespace
  labels:
    app: $DemoOneAppName
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $DemoOneAppName
  template:
    metadata:
      labels:
        app: $DemoOneAppName
    spec:
      containers:
      - name: whoami
        image: traefik/whoami:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "64Mi"
---
apiVersion: v1
kind: Service
metadata:  
  name: $DemoOneAppName
  namespace: $DemoOneNamespace
  labels:
    app: $DemoOneAppName
spec:
  type: ClusterIP
  selector:
    app: $DemoOneAppName
  ports:
  - port: 80
    targetPort: 80 
    protocol: TCP
    name: http
"@

$DemoOneDeployment | kubectl apply -f -

$HttpRouteDemoOne = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $DemoOneHttpRoute
  namespace: $DemoOneNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $GatewayNamespace
  hostnames:
    - "$DnsSubZoneOne" 
  rules:
    - matches:
      backendRefs:
        - name: $DemoOneAppName
          port: 80
"@

$HttpRouteDemoOne | kubectl apply -f -

kubectl get all -n $DemoOneNamespace

kubectl describe gateway -n $GatewayNamespace

curl https://$DnsSubZoneOne -UseBasicParsing
```

## Deploy second Test App
```
$DemoTwoDeployment = @"
apiVersion: v1
kind: Namespace
metadata:
  name: $DemoTwoNamespace
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${DemoTwoAppName}-deployment"
  namespace: $DemoTwoNamespace
  labels:
    app: $DemoTwoAppName
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $DemoTwoAppName
  template:
    metadata:
      labels:
        app: $DemoTwoAppName
    spec:
      containers:
      - name: whoami
        image: traefik/whoami:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "64Mi"
---
apiVersion: v1
kind: Service
metadata:  
  name: $DemoTwoAppName
  namespace: $DemoTwoNamespace
  labels:
    app: $DemoTwoAppName
spec:
  type: ClusterIP
  selector:
    app: $DemoTwoAppName
  ports:
  - port: 80
    targetPort: 80 
    protocol: TCP
    name: http
"@

$DemoTwoDeployment | kubectl apply -f -

$HttpRouteDemoTwo = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $DemoTwoHttpRoute
  namespace: $DemoTwoNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $GatewayNamespace
  hostnames:
    - "$DnsSubZoneTwo" 
  rules:
    - matches:
      backendRefs:
        - name: $DemoTwoAppName
          port: 80
"@

$HttpRouteDemoTwo | kubectl apply -f -

kubectl get all -n $DemoTwoNamespace

curl https://$DnsSubZoneTwo -UseBasicParsing
```
## Define Variables
```
$AksName="cert-manager-aks"
$Location="CanadaCentral"
$ResourceGroupName="cert-manager-rg"

$GatewayNamespace="envoy-gateway"
$GatewayName="gateway"
$GatewayClassName="envoy"
$HttpListenerName="http-listener"
$HttpsListenerName="demo-https-listener"
$WildcardListenerName="wildcard-https-listener"
$WildcardSecretName="wildcard-letsencrypt-secret"
$DemoSecretName="demo-letsencrypt-secret"

$ClusterIssuerName="letsencrypt"
$CertManagerNamespace="cert-manager"
$CertManagerManagedIdentityName="cert-manager"
$CertManagerServiceAccountName="cert-manager"

$DnsZoneName="programmingwithwolfgang.com" # Update with your DNS Zone Name
$DnsSubscriptionName="ProgrammingWithWolfgang" # Update with your Subscription
$DnsSubscriptionId=$(az account show --subscription "$DnsSubscriptionName" --query id --output tsv)
$DnsResourceGroup="ProgrammingWithWolfgang" # Update with your Resource Group

$DemoNamespace="demo-ns"
$DemoAppName="demo"
$DemoUrl="demo.programmingwithwolfgang.com" # Update with your URL
$WildcardNamespace="wildcard"
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
  --enable-workload-identity   

az aks get-credentials `
  --resource-group $ResourceGroupName `
  --name $AksName `
  --overwrite-existing
```

## Deploy Envoy and create the Gateway and GatewayClass
```
helm install envoy oci://docker.io/envoyproxy/gateway-helm `
  --version v1.7.0 `
  --namespace $GatewayNamespace `
  --create-namespace

kubectl get gateway -A
kubectl get gatewayclass

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
  - name: $HttpListenerName
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
  - name: $HttpsListenerName
    port: 443
    protocol: HTTPS
    hostname: $DemoUrl
    allowedRoutes:
      namespaces:
        from: All 
    tls:
      certificateRefs:
        - group: ""
          kind: Secret
          name: $DemoSecretName
  - name: $WildcardListenerName
    port: 443
    protocol: HTTPS
    hostname: "*.$DemoUrl"
    tls:
      certificateRefs:
        - group: ""
          kind: Secret
          name: $WildcardSecretName
          namespace: $GatewayNamespace    
    allowedRoutes:
      namespaces:
        from: All
"@

$Gateway | kubectl apply -f -

kubectl get gateway -n $GatewayNamespace 
kubectl describe gateway $GatewayName -n $GatewayNamespace
```

might take a minute to switch Programmed = True

```
kubectl get gatewayclass

kubectl get gateway $GatewayName -n $GatewayNamespace -o jsonpath='{.status.addresses[0].value}'
```

Update DNS

## Deploy Test App
```
$DemoDeployment = @"
apiVersion: v1
kind: Namespace
metadata:
  name: $DemoNamespace
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${DemoAppName}-deployment"
  namespace: $DemoNamespace
  labels:
    app: $DemoAppName
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $DemoAppName
  template:
    metadata:
      labels:
        app: $DemoAppName
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
  name: $DemoAppName
  namespace: $DemoNamespace
  labels:
    app: $DemoAppName
spec:
  type: ClusterIP
  selector:
    app: $DemoAppName
  ports:
  - port: 80
    targetPort: 80 
    protocol: TCP
    name: http
"@

$DemoDeployment | kubectl apply -f -

$HttpRouteDemoApp = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: demo-http-route
  namespace: $DemoNamespace  
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $GatewayNamespace
      sectionName: $HttpsListenerName
  hostnames:
    - "$DemoUrl" 
  rules:
    - matches:
      backendRefs:
        - name: $DemoAppName
          port: 80
"@

$HttpRouteDemoApp | kubectl apply -f -

kubectl get all -n $DemoNamespace

kubectl describe gateway -n $GatewayNamespace
```

## Install the Cert Manager and ClusterIssuer
```
helm repo add jetstack https://charts.jetstack.io --force-update
helm install `
  cert-manager jetstack/cert-manager `
  --namespace $CertManagerNamespace `
  --create-namespace `
  --version v1.19.4 `
  --set config.enableGatewayAPI=true `
  --set crds.enabled=true

$ClusterIssuer = @"
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: $ClusterIssuerName
spec:
  acme:
    # server: https://acme-v02.api.letsencrypt.org/directory # production endpoint
    server: https://acme-staging-v02.api.letsencrypt.org/directory # staging endpoint
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-private-key
    solvers:
      - http01:
          gatewayHTTPRoute:
            parentRefs:
              - name: $GatewayName
                namespace: $GatewayNamespace
                kind: Gateway
"@

$ClusterIssuer | kubectl apply -f -

kubectl get CertificateRequest -n $GatewayNamespace
kubectl get certificate -n $GatewayNamespace
kubectl get order -n $GatewayNamespace
kubectl get secret -n $GatewayNamespace
kubectl get ClusterIssuer -A -o yaml

$ClusterIssuer = @"
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: $ClusterIssuerName
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory # production endpoint
    # server: https://acme-staging-v02.api.letsencrypt.org/directory # staging endpoint
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-private-key
    solvers:
      - http01:
          gatewayHTTPRoute:
            parentRefs:
              - name: $GatewayName
                namespace: $GatewayNamespace
                kind: Gateway
"@

$ClusterIssuer | kubectl apply -f -

kubectl delete certificate demo-letsencrypt-secret -n $GatewayNamespace
kubectl delete order demo-letsencrypt-secret-1-256882364 -n $GatewayNamespace
kubectl delete secret demo-letsencrypt-secret -n $GatewayNamespace

curl https://$DemoUrl -UseBasicParsing
```

## Use Entra Workload Identity on the Cert Manager
Helm upgrade because the cert-manager was installed in the last video. If you don't have a cert-manager yet, use helm install

https://cert-manager.io/docs/configuration/acme/dns01/azuredns/

```
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
    email: your-email@example.com
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

## Deploy Wildcard Demo App
```
$DemoDeployment = @"
apiVersion: v1
kind: Namespace
metadata:
  name: $WildcardNamespace
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${DemoAppName}-deployment"
  namespace: $WildcardNamespace
  labels:
    app: $DemoAppName
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $DemoAppName
  template:
    metadata:
      labels:
        app: $DemoAppName
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
  name: $DemoAppName
  namespace: $WildcardNamespace
  labels:
    app: $DemoAppName
spec:
  type: ClusterIP
  selector:
    app: $DemoAppName
  ports:
  - port: 80
    targetPort: 80 
    protocol: TCP
    name: http
"@

$DemoDeployment | kubectl apply -f -

$HttpRouteDemoApp = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: wildcard-demo-http-route
  namespace: $WildcardNamespace  
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $GatewayNamespace
      sectionName: $WildcardListenerName
  hostnames:
    - "hello-world.$DemoUrl" 
  rules:
    - matches:
      backendRefs:
        - name: $DemoAppName
          port: 80
"@

$HttpRouteDemoApp | kubectl apply -f -

kubectl get all -n $WildcardNamespace

kubectl describe gateway -n $GatewayNamespace

curl https://hello-world.$DemoUrl -UseBasicParsing
```

## HTTP to HTTPs Redirect
```
curl http://$DemoUrl -UseBasicParsing

$RedirectRoute = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http-to-https-redirect
  namespace: $GatewayNamespace
spec:
  parentRefs:
  - name: $GatewayName
    namespace: $GatewayNamespace
    sectionName: $HttpListenerName
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        statusCode: 301
"@

$RedirectRoute | kubectl apply -f -

curl http://$DemoUrl -UseBasicParsing
```
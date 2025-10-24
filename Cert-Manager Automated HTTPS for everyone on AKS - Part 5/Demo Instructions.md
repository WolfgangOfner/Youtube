## Define Variables
```
$InfrastructureNamespace="alb-infra"
$GatewayName="gateway"
$GatewayClassName="azure-alb-external"
$ApplicationLoadBalancerName="application-load-balancer"
$ClusterIssuerName="letsencrypt-prod"

$NginxNamespace="nginx-ns"
$NginxHttpRoute="nginx-http-route"
$NginxAppName="nginx"
$NginxCertificateName="nginx-letsencrypt-cert"
$NginxSecretName="nginx-letsencrypt-secret"
$NginxUrl="nginx.programmingwithwolfgang.com"

$TraefikNamespace="traefik-ns"
$TraefikHttpRoute="traefik-http-route"
$TraefikAppName="traefik"
$TraefikCertificateName="traefik-letsencrypt-cert"
$TraefikSecretName="traefik-letsencrypt-secret"
$TraefikUrl="traefik.programmingwithwolfgang.com"
```

## Install the Cert Manager and ClusterIssuer
```
helm repo add jetstack https://charts.jetstack.io --force-update
helm install `
  cert-manager jetstack/cert-manager `
  --namespace cert-manager `
  --create-namespace `
  --version v1.17.1 `
  --set config.enableGatewayAPI=true `
  --set crds.enabled=true

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
"@

$ClusterIssuer | kubectl apply -f -

kubectl get ClusterIssuer -A -o yaml
```

Status should be True and type be Ready

## Create Certificates for the Test Applications
```
$TraefikCertificate = @"
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: $TraefikCertificateName
  namespace: $InfrastructureNamespace
spec:
  secretName: $TraefikSecretName
  issuerRef:
    name: $ClusterIssuerName
    kind: ClusterIssuer
  dnsNames:
    - $TraefikUrl
"@

$TraefikCertificate | kubectl apply -f -

kubectl get certificate $TraefikCertificateName -n $InfrastructureNamespace
kubectl get challenges -n $InfrastructureNamespace -o yaml

$NginxCertificate = @"
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: $NginxCertificateName
  namespace: $InfrastructureNamespace
spec:
  secretName: $NginxSecretName
  issuerRef:
    name: $ClusterIssuerName
    kind: ClusterIssuer
  dnsNames:
    - $NginxUrl
"@

$NginxCertificate | kubectl apply -f -

kubectl get certificate $NginxCertificateName -n $InfrastructureNamespace
kubectl get challenges -n $InfrastructureNamespace -o yaml
```

## Update the Gateway to listen for HTTPS
```
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
"@

$Gateway | kubectl apply -f -

kubectl get gateway $GatewayName -n $InfrastructureNamespace -o yaml
```

## Update the HTTPRoutes of the Test Apps 

The updates are not necessary because the HTTPRoutes already have the proper configuration from the last video but this section helps to clarify how hostnames work.

```
$HttpRouteTraefik = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $TraefikHttpRoute
  namespace: $TraefikNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $InfrastructureNamespace
  hostnames:
    - "$TraefikUrl" 
  rules:
    - matches:
      backendRefs:
        - name: $TraefikAppName
          port: 80
"@

$HttpRouteTraefik | kubectl apply -f -

$HttpRouteNginx = @"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $NginxHttpRoute
  namespace: $NginxNamespace
spec:
  parentRefs:
    - name: $GatewayName
      namespace: $InfrastructureNamespace 
  hostnames:
    - "$NginxUrl" 
  rules:
    - matches:
      backendRefs:
        - name: $NginxAppName
          port: 80
"@

$HttpRouteNginx | kubectl apply -f -
```

Note: The TLS secrets are in the infrastructre namespace. I like this approach because it belongs to the infrastructure and not software development. Additionally, if the secret was in the namespace of the application, you would need to create a ReferenceGrant to allow access from the infrastructure namespace to the secret.
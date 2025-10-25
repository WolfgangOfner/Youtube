## Steps

- Create CNAME Record to point to gateway hostname
- Create wildcard certificate and configure listener on gateway
- Have a pipeline/stage/job that only runs for pull requests
- Enforce in pull request policy that pipeline must run

Azure DevOps pipelines:
- PR-Deployment-CI.yaml
- PR-Deployment-CD.yaml


## Get Hostname
```
$InfrastructureNamespace="alb-infra"
$GatewayName="gateway"

kubectl get gateway $GatewayName -n $InfrastructureNamespace -o yaml
kubectl get gateway $GatewayName -n $InfrastructureNamespace -o jsonpath='{.status.addresses[0].value}'
```
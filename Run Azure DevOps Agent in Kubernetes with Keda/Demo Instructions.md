- Agent.Dockerfile
- start.sh
### start.sh file ending must be LF, Windows creates it with CRLF

docker build -f .\Agent.Dockerfile . -t adoagent

docker run -e AZP_URL=https://dev.azure.com/programmingwithwolfgang -e AZP_TOKEN=<Your_PAT> -e AZP_AGENT_NAME=agent -e AZP_POOL=AgentInContainer adoagent

docker tag adoagent wolfgangofner/adoagent:1

docker push wolfgangofner/adoagent:1

## Get PAT from ADO

echo '<Your_PAT>' | base64

## Install Keda
- https://keda.sh/
- scaling can be  based on external sources, scale to 0
- 
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace

## Deploy Agent in Kubernetes
kubectl create ns adoagent

kubectl config set-context --current --namespace=adoagent

kubectl apply -f ./deployment.yaml

kubectl get pod --watch

deactivate agent

kubectl apply -f ./keda-scaled-jobs.yaml

kubectl get pod --watch

## Add .NET SDK to Agent
docker build -f .\AgentWithTools.Dockerfile . -t adoagent
docker tag adoagent wolfgangofner/adoagent:2

docker push wolfgangofner/adoagent:2

- Update iamge in keda-scaled-jobs.yaml
kubectl apply -f ./keda-scaled-jobs.yaml

## Add Podman to Agent
docker build -f .\AgentWithTools.Dockerfile . -t adoagent
docker tag adoagent wolfgangofner/adoagent:3

docker push wolfgangofner/adoagent:3
- Update keda-scaled-jobs.yaml
kubectl apply -f ./keda-scaled-jobs.yaml

- Enable security context
kubectl apply -f ./keda-scaled-jobs.yaml

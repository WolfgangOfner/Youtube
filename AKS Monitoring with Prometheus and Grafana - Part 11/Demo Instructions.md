## Define Variables
```
$ResourceGroupName="app-gateway-container-rg"
$LogAnalyticsName="app-gateway-log"
```

## Create new Log Analytics Workspace
```
az monitor log-analytics workspace create `
    --resource-group $ResourceGroupName `
    --name $LogAnalyticsName
```

Enable logs in ALB

## Send Requests to see something in the Logs and Metrics 
```
TraefikUrl="traefik.programmingwithwolfgang.com"
watch -n 0.1 curl https://$TraefikUrl

watch -n 1 curl http://$TraefikUrl

watch -n 0.5 curl http://$RoutingUrl/my/path
```

## Configure AKS and Grafana 

AKS --> Insights --> Monitor Settings
enable everything
leave advanced settings as is (new Azure Monitor workspace and Grafana instance, re-use Log Analytics workspace from before) 

Update file prometheus-configmap.yaml and change podannotationnamespaceregex=<ALB_NAMESPACE_NAME> e.g. podannotationnamespaceregex = "alb-infra"
This file configures the Azure Monitor Agent inside the AKS cluster (e.g. enables Promtheus Scraping)

```
kubectl apply -f .\prometheus-configmap.yaml
```

Assign the Monitoring Reader role. Should be enough on alb and log.

wait a bit for the permission to propagate

Open Grafana
new dashboard
Prometheus as data source

new dashboard
Azure Monitor
Change Service to Logs
Select Ressource --> Log Analytics Workspace

```
KubePodInventory
| where TimeGenerated > ago(5m)
| where PodStatus == "Running"
| summarize RunningPodCount = count() by Namespace
| order by RunningPodCount desc
```

new dashboard
Azure Monitor
Keep Metrics
Select Ressource --> Log Analytics Workspace
HTTP Response Status {{httpresponsecode}}
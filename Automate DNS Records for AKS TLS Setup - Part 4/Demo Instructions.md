## Define Variables
```
$DnsRecords=@('nginx','traefik','routing','*.pullrequest','*.customer','*.order','*.kedademo', 'customer','order','kedademo')
$DnsResourceGroupName="ProgrammingWithWolfgang"
$DnsZoneName="programmingwithwolfgang.com"

$GatewayName="gateway"
$InfrastructureNamespace="alb-infra"
$Fqdn=$(kubectl get gateway $GatewayName -n $InfrastructureNamespace -o jsonpath='{.status.addresses[0].value}')
```

## Create or Update CNAME Records for FQDN of Gateway
```
kubectl get gateway $GatewayName -n $InfrastructureNamespace -o yaml

ForEach ($dnsRecord in $DnsRecords) {
    $recordExists = `
        az network dns record-set cname show `
        --resource-group $DnsResourceGroupName `
        --zone-name $DnsZoneName `
        --name $dnsRecord 2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Create Cname record for: ${dnsRecord}"
        az network dns record-set cname create `
            --resource-group $DnsResourceGroupName `
            --zone-name $DnsZoneName `
            --name $dnsRecord `
            --output none
    } 

    Write-Host "Update Cname record for: ${dnsRecord}"
    az network dns record-set cname update `
        --resource-group $DnsResourceGroupName `
        --zone-name $DnsZoneName `
        --name $dnsRecord `
        --set cname_record.cname=$Fqdn `
        --output none   
}
```
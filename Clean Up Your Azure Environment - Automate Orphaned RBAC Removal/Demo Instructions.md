## Get rophaned RoleAssignments locally
```
az role assignment list `
    --all `
    --query "[?DisplayName==null || SignInName=='']"

Install-Module -Name Az -AllowClobber -Scope CurrentUser
Update-AzConfig -EnableLoginByWam $false
Connect-AzAccount

$OrphanedRoleAssignments = Get-AzRoleAssignment | Where-Object {
     [string]::IsNullOrWhiteSpace($_.DisplayName) -and
     [string]::IsNullOrWhiteSpace($_.SignInName)
 }

$OrphanedRoleAssignments | Select-Object RoleDefinitionName, Scope, ObjectId, DisplayName
```

## Define Variables
```
$Location="CanadaCentral"
$ResourceGroupName="cleanup-rolebindings-rg"
$AutomationAccountName="cleanup-rolebindings-aa"
$SubscriptionId=$(az account show --query id --output tsv)
```

## Create Automation Account
```
az group create `
    --name $ResourceGroupName `
    --location $Location

az automation account create `
    --resource-group $ResourceGroupName `
    --automation-account-name $AutomationAccountName `
    --sku Free

az resource update `
    --resource-group $ResourceGroupName `
    --name $AutomationAccountName `
    --resource-type "Microsoft.Automation/automationAccounts" `
    --set identity.type="SystemAssigned"

$PrincipalId=$(az resource show `
    --resource-group $ResourceGroupName `
    --name $AutomationAccountName `
    --resource-type "Microsoft.Automation/automationAccounts" `
    --query identity.principalId `
    --output tsv)

az role assignment create `
    --assignee-object-id $PrincipalId `
    --assignee-principal-type ServicePrincipal `
    --role "Role Based Access Control Administrator" `
    --scope "/subscriptions/$SubscriptionId"
```

## Create Automation Account Workbook
```
Connect-AzAccount -Identity 

$OrphanedRoleAssignments = Get-AzRoleAssignment | Where-Object { 
    [string]::IsNullOrWhiteSpace($_.DisplayName) -and 
    [string]::IsNullOrWhiteSpace($_.SignInName) 
}

foreach ($OrphanedRoleAssignment in $OrphanedRoleAssignments) {
    Write-Output "Removing orphaned assignment: $($OrphanedRoleAssignment.RoleDefinitionName) for ID: $($OrphanedRoleAssignment.ObjectId)"
    
    Remove-AzRoleAssignment -ObjectId $OrphanedRoleAssignment.ObjectId `
                            -Scope $OrphanedRoleAssignment.Scope `
                            -RoleDefinitionName $OrphanedRoleAssignment.RoleDefinitionName `
                            -WhatIf

    Remove-AzRoleAssignment -ObjectId $OrphanedRoleAssignment.ObjectId `
                            -Scope $OrphanedRoleAssignment.Scope `
                            -RoleDefinitionName $OrphanedRoleAssignment.RoleDefinitionName
}
```
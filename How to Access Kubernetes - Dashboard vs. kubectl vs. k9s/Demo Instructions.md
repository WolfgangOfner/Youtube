## Define Variables
```
$ResourceGroupName="k8s-access-demo"
$Location="CanadaCentral"
$AksName="k8s-access-aks"
```

## Create RG and AKS Cluster
```
az group create `
    --name $ResourceGroupName `
    --location $Location

az aks create `
    --name $AksName `
    --resource-group $ResourceGroupName

az aks get-credentials `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing
```

## k Alias on Windows
```
Set-Alias -Name k -Value kubectl
kubectl completion powershell | Out-String | Invoke-Expression
Register-ArgumentCompleter -CommandName k -ScriptBlock $__kubectlCompleterBlock

notepad $PROFILE
New-Item -ItemType File -Force -Path $PROFILE

# 1. Ensure the alias exists
Set-Alias -Name k -Value kubectl

# 2. Load the base kubectl completion (only if kubectl is found)
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    # We generate it once and invoke it
    $kubectlCompletion = kubectl completion powershell | Out-String
    Invoke-Expression $kubectlCompletion
}

# 3. Create the bridge for 'k'
# This ensures that when you tab on 'k', it looks up 'kubectl' logic
Register-ArgumentCompleter -CommandName 'k' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    [Microsoft.PowerShell.Commands.CompletionCompleters]::CompleteArgument(
        "kubectl", $wordToComplete, $commandAst, $cursorPosition)
}
```

## k Alias on Linux
```
az aks get-credentials --resource-group k8s-access-demo --name k8s-access-aks --overwrite-existing

alias k=kubectl
complete -o default -F __start_kubectl k
```

## K9s
```
wget https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb && sudo apt install ./k9s_linux_amd64.deb && rm k9s_linux_amd64.deb

k9s

:
ns

Shift+s
Ctrl+w

:
deploy
s --> scale

:
secrets
x
```
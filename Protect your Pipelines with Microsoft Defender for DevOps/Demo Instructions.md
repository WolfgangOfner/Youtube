Defender Installation
PR Deployments
Extensions
- Microsoft Security DevOps
- Sarif SAST Scans Tab
Demo project


## Pipeline Task

```
steps:
- task: MicrosoftSecurityDevOps@1
  displayName: 'Microsoft Security DevOps'
  # inputs:    
    # config: string. Optional. A file path to an MSDO configuration file ('*.gdnconfig'). Vist the MSDO GitHub wiki linked below for additional configuration instructions
    # policy: 'azuredevops' | 'microsoft' | 'none'. Optional. The name of a well-known Microsoft policy to determine the tools/checks to run. If no configuration file or list of tools is provided, the policy may instruct MSDO which tools to run. Default: azuredevops.
    # categories: string. Optional. A comma-separated list of analyzer categories to run. Values: 'code', 'artifacts', 'IaC', 'containers'. Example: 'IaC, containers'. Defaults to all.
    # languages: string. Optional. A comma-separated list of languages to analyze. Example: 'javascript,typescript'. Defaults to all.
    # tools: string. Optional. A comma-separated list of analyzer tools to run. Values: 'bandit', 'binskim', 'checkov', 'eslint', 'templateanalyzer', 'terrascan', 'trivy'. Example 'templateanalyzer, trivy'
    # break: boolean. Optional. If true, will fail this build step if any high severity level results are found. Default: false.
    # publish: boolean. Optional. If true, will publish the output SARIF results file to the chosen pipeline artifact. Default: true.
    # artifactName: string. Optional. The name of the pipeline artifact to publish the SARIF result file to. Default: CodeAnalysisLogs*. 
```

https://github.com/microsoft/security-devops-azdevops
https://learn.microsoft.com/en-us/azure/defender-for-cloud/container-image-mapping
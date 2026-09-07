# Repo credentials for the POC (PAT)

Azure DevOps PAT scoped to `Code (Read)` on the `Developer Platform Playground` project.

Create a declarative repo-creds Secret (do not commit the real PAT to git):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ado-developer-platform-playground-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  url: https://dev.azure.com/programmingwithwolfgang/Youtube
  username: pat            # any non-empty value works, ADO ignores it
  password: <PAT_VALUE>     # inject via kubectl create secret / sealed-secrets / vault, never hardcode
```

Apply with:
```
kubectl apply -f ado-repo-creds.yaml -n argocd
```

One `repo-creds` entry per ADO **project** covers all repos under that project prefix, so onboarding a new team under the same ADO project needs no new credential.

## Fallback: per-repository secret

If the ApplicationSet controller reports authentication errors against the git generator (prefix matching with the `%20` in the project name is the usual suspect), register the repo explicitly instead:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ado-gitops-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://dev.azure.com/programmingwithwolfgang/Youtube/_git/Team-a
  username: pat
  password: <PAT_VALUE>
```

## Future: swapping to Service Principal / federated auth
Replace the `password` field flow with ArgoCD's OIDC/workload-identity based repo auth once validated for your ADO tenant. Re-verify current support against ArgoCD's official docs before relying on it in production, since this POC intentionally used PAT for speed.

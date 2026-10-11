---
paths:
  - "k8s/**"
---

# Kubernetes manifests (Flux)

- CI publishes `k8s/` as an OCI artifact. On the cluster, four Flux Kustomizations apply it in order: `infrastructure` and `namespaces`, then `instrumentation` (after namespaces), then `app` (after infrastructure and instrumentation). They are defined in `infra/modules/compute/aks.bicep`, not in `k8s/`.
- `${PLACEHOLDERS}` are filled from `manifestValues` with strict substitution, so one with no value stops the rollout. A new placeholder goes into `manifestValues` in `infra/main.bicep` and into the values list of the "Validate the Kubernetes manifests" step in `.github/workflows/ci.yml`.
- Validate as CI does: copy that step's values into `scratch/flux/values.env`, then run `flux schema validate k8s --schema-location default --schema-location ecosystem --envsubst-file scratch/flux/values.env --envsubst-strict --skip-kind monitor.azure.com/v1/Instrumentation` (needs the Flux `schema` plugin).
- Keep `kustomize.toolkit.fluxcd.io/prune: disabled` on the namespaces: `namespaces.yaml` explains why.
- AKS ships an older Flux than fluxcd.io describes; the `microsoft.flux` extension release notes on Microsoft Learn give its version. Rehearse on kind with that version, and say "verified on kind, not on AKS" until the cluster confirms it.
- Read the live cluster through `scratch/aks/aks.kubeconfig`, never `~/.kube/config`: `az aks get-credentials --file scratch/aks/aks.kubeconfig`, then `sed -i.bak -E 's/^( *- )(devicecode|interactive)$/\1azurecli/' scratch/aks/aks.kubeconfig` and `kubectl --kubeconfig scratch/aks/aks.kubeconfig`. Don't run `kubelogin convert-kubeconfig`.

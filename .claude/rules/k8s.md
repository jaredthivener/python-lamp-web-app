---
paths:
  - "k8s/**"
---

# Kubernetes manifests (Flux)

- CI publishes `k8s/` as an OCI artifact. On the cluster, five Flux Kustomizations apply it: `infrastructure`, `namespaces` and `monitoring` first (independent of each other), then `observability` (the OpenTelemetry collector; after namespaces), then `app` (after infrastructure and observability). They are defined in `infra/modules/compute/aks.bicep`, not in `k8s/`.
- `${PLACEHOLDERS}` are filled from `manifestValues` with strict substitution, so one with no value stops the rollout. A new placeholder goes into `manifestValues` in `infra/main.bicep` and into the values list of the "Validate the Kubernetes manifests" step in `.github/workflows/ci.yml`.
- Validate as CI does: copy that step's values into `scratch/flux/values.env`, then run `flux schema validate k8s --schema-location default --schema-location ecosystem --envsubst-file scratch/flux/values.env --envsubst-strict --skip-kind azmonitoring.coreos.com/v1/PodMonitor` (needs the Flux `schema` plugin). The PodMonitors in `k8s/monitoring` use the managed add-on's CRD, which has no published schema: validate them against the CRD in `Azure/prometheus-collector` (`otelcollector/deploy/addon-chart/azure-monitor-metrics-addon/templates/ama-metrics-podmonitor-crd.yaml`) with a JSON Schema validator, and know that it catches wrong types and missing fields, not misspelled ones. The collector's configuration is not a Kubernetes object, so `.github/scripts/validate-collector.sh scratch/flux/values.env` checks it with the pinned collector image (needs Docker and the Flux CLI). In `k8s/observability`, the collector's own `${env:X}` is written `$${env:X}`: Flux turns `$$` into `$`.
- Keep `kustomize.toolkit.fluxcd.io/prune: disabled` on the namespaces: `namespaces.yaml` explains why.
- AKS ships an older Flux than fluxcd.io describes; the `microsoft.flux` extension release notes on Microsoft Learn give its version. Rehearse on kind with that version, and say "verified on kind, not on AKS" until the cluster confirms it.
- Read the live cluster through `scratch/aks/aks.kubeconfig`, never `~/.kube/config`: `az aks get-credentials --file scratch/aks/aks.kubeconfig`, then `sed -i.bak -E 's/^( *- )(devicecode|interactive)$/\1azurecli/' scratch/aks/aks.kubeconfig` and `kubectl --kubeconfig scratch/aks/aks.kubeconfig`. Don't run `kubelogin convert-kubeconfig`.

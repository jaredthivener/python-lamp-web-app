---
name: verify-live
description: Check the deployed Azure environment end to end - cluster running, site answering with PostgreSQL behind it, Flux Kustomizations Ready, lamp pods up, OpenTelemetry collector running and spans arriving. Use after a deploy, or when asked whether the live site works.
argument-hint: "[environment, default dev]"
context: fork
agent: general-purpose
background: false
model: haiku
effort: low
allowed-tools:
  - Bash(az group exists *)
  - Bash(az aks list *)
  - Bash(az aks show *)
  - Bash(az network public-ip list *)
  - Bash(az aks get-credentials *)
  - Bash(az alerts-management prometheus-rule-group list *)
  - Bash(az grafana dashboard list *)
  - Bash(az grafana list *)
  - Bash(mkdir -p scratch/*)
  - Bash(kubectl --kubeconfig *)
---

Environment: `$ARGUMENTS` (use `dev` if that is empty). The resource group is `rg-lamp-web-app-<environment>`. Change nothing.

Run every check, then report a table: check, result, and the output that shows it. A check you could not run is reported as not run, with the reason.

1. **It exists.** `az group exists -n <group>`. If `false`, report that nothing is deployed and stop.
2. **The cluster runs.** `az aks list -g <group> --query "[0].name" -o tsv`, then `az aks show -g <group> -n <cluster> --query "{power:powerState.code,state:provisioningState,kubernetes:kubernetesVersion}"`. Expect `Running` and `Succeeded`.
3. **The site answers.** `az network public-ip list -g <group> --query "[?dnsSettings.fqdn].dnsSettings.fqdn" -o tsv` gives the host. `curl -s https://<host>/health` should return `{"status":"healthy","database":"postgresql"}`; `degraded` means the pods cannot reach PostgreSQL. After a start or a first deploy the site takes 5 to 14 minutes to answer (infra/README.md, "What a start looks like").
4. **Flux applied everything.** Write credentials to `scratch/aks/` in the repository (`mkdir -p scratch/aks`), never to `~/.kube/config` or a temp directory:
   `az aks get-credentials -g <group> -n <cluster> --file scratch/aks/aks.kubeconfig`, then
   `sed -i.bak -E 's/^( *- )(devicecode|interactive)$/\1azurecli/' scratch/aks/aks.kubeconfig`.
   `kubectl --kubeconfig scratch/aks/aks.kubeconfig get kustomizations,ocirepositories,helmreleases -n flux-system`: every row should be `READY True`. Name any that is not, with its message.
5. **The app runs.** `kubectl --kubeconfig scratch/aks/aks.kubeconfig -n lamp get pods -l app=lamp-app -o wide`: two pods, `Running`, on different nodes.
6. **Telemetry is wired.** `kubectl --kubeconfig scratch/aks/aks.kubeconfig -n observability get pods` shows two `otel-gateway` pods `Running`, and `kubectl --kubeconfig scratch/aks/aks.kubeconfig -n observability logs deploy/otel-gateway --tail=30` has no `Exporting failed` lines (`Unauthenticated` means the collector's workload identity or its role on the data collection rule is wrong). The app's pods should list `OTEL_EXPORTER_OTLP_ENDPOINT` among their env names. Then the data itself: `az monitor log-analytics query --workspace <customerId of the lamp-logs-* workspace> --analytics-query "OTelSpans | where TimeGenerated > ago(10m) | summarize count() by ServiceName"` should list `lamp-app` after a few requests to the site. Name what is missing.
7. **Monitoring is complete.** `az alerts-management prometheus-rule-group list -g <group> --query '[].{name:name,rules:length(properties.rules),enabled:properties.enabled}'` shows one enabled group with 19 rules. `az grafana dashboard list -g <group> -n <grafana> --query "[?contains(uid,'k8s-') || uid=='lamp-api'].uid"` lists `lamp-api` and the six `k8s-*` dashboards. Then, for each dashboard, run its queries through Grafana (`/api/ds/query`, as `infra/README.md` describes) and name any panel with no data that is not explained by an absence of events. `kubectl --kubeconfig scratch/aks/aks.kubeconfig -n kube-system get configmap ama-metrics-settings-configmap` exists and the `lamp-monitoring` Kustomization is `READY True`.

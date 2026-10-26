// =============================================================================
// Alert rules for the cluster and the app
// =============================================================================
// One Prometheus rule group on the Azure Monitor workspace: Azure evaluates the PromQL itself, every
// minute, and fires into an action group that emails the owner. Dashboards show; these tell. The
// signals are the ones the dashboards in infra/dashboards chart, so a firing alert has a panel to
// open. Severity is Azure's scale: 0 critical, 1 error, 2 warning, 3 informational, 4 verbose.
// https://learn.microsoft.com/azure/azure-monitor/essentials/prometheus-rule-groups
//
// Where a rule exists in Microsoft's recommended alert rules for Kubernetes (Azure/prometheus-collector,
// GeneratedMonitoringArtifacts/Default/recommendedMetricAlerts.json) this follows its PromQL and `for`:
// KubePodCrashLooping (max_over_time over 5m: the plain series flickers between waiting and terminated, and a
// 15-minute `for` never completed against a pod that had been in CrashLoopBackOff for 50 minutes),
// KubeDeploymentReplicasMismatch (not while a rollout is in progress) and the 80% node disk threshold.
// Severities, the thresholds of the other rules and the Envoy, CoreDNS, certificate and lamp rules are chosen here, not Microsoft's.
// ContainerOOMKilled differs from Microsoft's KubeContainerOOMKilledCount on purpose: it needs a restart in the
// last 10 minutes, so it clears when the container stops being killed instead of staying until the pod is replaced.
//
// A rule that means "this is down" is written so that missing data is NOT down: on a new cluster the
// metrics take 10 to 20 minutes to start arriving, and `or vector(0)` turned that into two Sev1 alerts
// that stayed fired for 10 minutes after (seen on the first deploy). kube-state-metrics reports a
// Deployment's available replicas, so zero is a series with value 0, and no data is no alert.
//
// .github/scripts/check-promql.py reads the `alert:` and `expression:` lines below and checks that each
// expression parses (so keep each on one line, with PromQL's double quotes, never a single quote).
// =============================================================================

@description('Resource ID of the Azure Monitor workspace the rules read from')
param monitorWorkspaceId string

@description('The name the rule group and the action group are named after')
param name string

@description('The Azure region of the workspace')
param location string

@description('Tags to apply to the resources')
param tags object = {}

@description('Alerts at this severity number or lower notify the action group (0 critical, 1 error, 2 warning, 3 informational, 4 verbose). The rest show in the portal under Alerts only. Set to 1: this is the owner of a practice environment, and an email per warning (and per resolution) was too many.')
@minValue(0)
@maxValue(4)
param maxNotifiedSeverity int = 1

@description('Where alerts are emailed. Empty creates the rules without notifications: they still fire, and show in the portal under Alerts.')
@secure()
param alertEmail string = ''

var alertRules = [
  {
    alert: 'KubeNodeNotReady'
    expression: 'sum(kube_node_status_condition{condition="Ready",status=~"false|unknown"}) > 0'
    for: 'PT10M'
    severity: 2
    summary: 'A node has not been Ready for 10 minutes. Pods on it are being rescheduled, or are stuck.'
  }
  {
    alert: 'KubePodCrashLooping'
    expression: 'max_over_time(kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}[5m]) >= 1'
    for: 'PT15M'
    severity: 2
    summary: 'A container has been in CrashLoopBackOff for 15 minutes.'
  }
  {
    alert: 'KubePodNotScheduled'
    expression: 'sum by (namespace, pod)(kube_pod_status_phase{phase=~"Pending|Unknown"}) > 0'
    for: 'PT15M'
    severity: 3
    summary: 'A pod has been Pending or Unknown for 15 minutes: usually not enough CPU or memory left on the nodes, or an image that cannot be pulled.'
  }
  {
    alert: 'KubeDeploymentReplicasMismatch'
    expression: '(kube_deployment_spec_replicas > kube_deployment_status_replicas_available) and (changes(kube_deployment_status_replicas_updated[10m]) == 0)'
    for: 'PT15M'
    severity: 2
    summary: 'A Deployment has had fewer available replicas than it wants for 15 minutes, and is not mid-rollout (its updated replica count has not changed in 10 minutes).'
  }
  {
    alert: 'ContainerOOMKilled'
    expression: 'increase(kube_pod_container_status_restarts_total[10m]) > 0 and on (namespace, pod, container) kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1'
    for: 'PT1M' // Azure refuses PT0M: the shortest is a minute
    severity: 2
    summary: 'A container was killed for running out of memory and restarted.'
  }
  {
    alert: 'NodeMemoryHigh'
    expression: '(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.9'
    for: 'PT15M'
    severity: 3
    summary: 'A node has used over 90% of its memory for 15 minutes.'
  }
  {
    alert: 'NodeFilesystemFilling'
    expression: '(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) > 0.80'
    for: 'PT15M'
    severity: 3
    summary: 'A node root filesystem is over 80% full.'
  }
  {
    alert: 'KubeCPUOvercommit'
    expression: 'sum(kube_pod_container_resource_requests{resource="cpu"}) / sum(kube_node_status_allocatable{resource="cpu"}) > 0.9'
    for: 'PT30M'
    severity: 3
    summary: 'Pods have reserved over 90% of the nodes CPU: the next pod, or a node failure, will leave something Pending.'
  }
  {
    alert: 'CoreDNSDown'
    expression: 'kube_deployment_status_replicas_available{namespace="kube-system",deployment="coredns"} < 1'
    for: 'PT5M'
    severity: 1
    summary: 'No CoreDNS replica is available: nothing in the cluster can resolve names.'
  }
  {
    alert: 'CoreDNSHighLatency'
    expression: 'histogram_quantile(0.99, sum by (le)(rate(coredns_dns_request_duration_seconds_bucket[5m]))) > 0.25'
    for: 'PT10M'
    severity: 3
    summary: 'Cluster DNS p99 latency has been over 250 ms for 10 minutes.'
  }
  {
    alert: 'CoreDNSServfailRatio'
    expression: 'sum(rate(coredns_dns_responses_total{rcode=~"SERVFAIL|REFUSED"}[5m])) / sum(rate(coredns_dns_responses_total[5m])) > 0.01'
    for: 'PT10M'
    severity: 2
    summary: 'Over 1% of DNS lookups have failed (SERVFAIL or REFUSED) for 10 minutes.'
  }
  {
    alert: 'ApiServerErrors'
    expression: 'sum(rate(apiserver_request_total{code=~"5.."}[5m])) / sum(rate(apiserver_request_total[5m])) > 0.02'
    for: 'PT10M'
    severity: 2
    summary: 'Over 2% of API server requests have returned a 5xx for 10 minutes.'
  }
  {
    alert: 'CertificateRenewalOverdue'
    expression: '(time() - certmanager_certificate_renewal_timestamp_seconds) > 86400'
    for: 'PT1H'
    severity: 2
    summary: 'cert-manager should have renewed a certificate more than a day ago (its own renewal time, 2/3 of the way through the lifetime by default) and has not.'
  }
  {
    alert: 'CertificateExpiringSoon'
    expression: '(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400 < 7'
    for: 'PT1H'
    severity: 1
    summary: 'A certificate expires in under 7 days: the backstop for a renewal that did not happen.'
  }
  {
    alert: 'CertificateNotReady'
    expression: 'certmanager_certificate_ready_status{condition="True"} == 0'
    for: 'PT30M'
    severity: 2
    summary: 'A certificate has not been Ready for 30 minutes.'
  }
  {
    alert: 'FluxReconcileErrors'
    expression: 'sum by (controller)(rate(controller_runtime_reconcile_errors_total[10m])) > 0'
    for: 'PT30M'
    severity: 3
    summary: 'A Flux controller has had reconcile errors for 30 minutes: what CI published is not being applied.'
  }
  {
    alert: 'EnvoyProxyDown'
    expression: 'kube_deployment_status_replicas_available{namespace="envoy-gateway-system",deployment="public-gateway"} < 1'
    for: 'PT5M'
    severity: 1
    summary: 'No replica of the public gateway proxy (the Deployment named after the Gateway in k8s/app/public-gateway.yaml) is available: the site is unreachable.'
  }
  {
    alert: 'EnvoyHigh5xx'
    expression: 'sum(rate(envoy_http_downstream_rq_xx{envoy_response_code_class="5"}[5m])) / sum(rate(envoy_http_downstream_rq_total[5m])) > 0.05'
    for: 'PT10M'
    severity: 2
    summary: 'Over 5% of requests at the gateway have returned a 5xx for 10 minutes.'
  }
  {
    alert: 'LampAppHigh5xx'
    expression: 'sum(histogram_count(sum_over_time({"http.server.request.duration","service.name"="lamp-app","http.route"!="/api/v1/lamp/events","http.response.status_code"=~"5.."}[10m]))) / sum(histogram_count(sum_over_time({"http.server.request.duration","service.name"="lamp-app","http.route"!="/api/v1/lamp/events"}[10m]))) > 0.05'
    for: 'PT10M'
    severity: 2
    summary: 'Over 5% of the lamp API requests have returned a 5xx for 10 minutes (the event stream is not counted).'
  }
  {
    alert: 'LampAppReplicasMissing'
    expression: 'count(count by ("k8s.pod.name")(last_over_time({"http.server.active_requests","service.name"="lamp-app"}[10m]))) < 2'
    for: 'PT15M'
    severity: 3
    summary: 'Fewer than two lamp-app replicas have reported telemetry for 15 minutes.'
  }
]

resource workspace 'Microsoft.Monitor/accounts@2025-10-03' existing = {
  name: last(split(monitorWorkspaceId, '/'))
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (!empty(alertEmail)) {
  name: '${name}-alerts'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'lamp-alerts' // the name in the notification, at most 12 characters
    enabled: true
    emailReceivers: [
      {
        name: 'owner'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

resource ruleGroup 'Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01' = {
  name: '${name}-alerts'
  location: location
  tags: tags
  properties: {
    description: 'Cluster, platform and lamp-app alerts (infra/modules/monitor/alerts.bicep)'
    enabled: true
    interval: 'PT1M'
    scopes: [workspace.id]
    rules: [for rule in alertRules: {
      alert: rule.alert
      expression: rule.expression
      for: rule.for
      severity: rule.severity
      enabled: true
      labels: {
        severity: string(rule.severity)
      }
      annotations: {
        summary: rule.summary
      }
      resolveConfiguration: {
        autoResolved: true
        timeToResolve: 'PT10M'
      }
      actions: empty(alertEmail) || rule.severity > maxNotifiedSeverity ? [] : [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }]
  }
}

// A stateful alert sends a second notification when it resolves, by email as well
// (https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-overview#stateful-alerts). An alert
// processing rule that removes the action groups from alerts whose monitor condition is Resolved keeps
// the fired notification and drops that one; the resolution still shows in the portal. Scoped to this
// resource group. Azure says a new or changed rule can take up to 30 minutes to take effect.
// https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-processing-rules
resource suppressResolved 'Microsoft.AlertsManagement/actionRules@2021-08-08' = {
  name: '${name}-no-resolved-notifications'
  location: 'global'
  tags: tags
  properties: {
    description: 'No notification when an alert resolves: the fired one already told the owner (infra/modules/monitor/alerts.bicep)'
    scopes: [resourceGroup().id]
    conditions: [
      {
        field: 'MonitorCondition'
        operator: 'Equals'
        values: ['Resolved']
      }
    ]
    actions: [
      {
        actionType: 'RemoveAllActionGroups'
      }
    ]
    enabled: true
  }
}

@description('The rule group')
output ruleGroupName string = ruleGroup.name

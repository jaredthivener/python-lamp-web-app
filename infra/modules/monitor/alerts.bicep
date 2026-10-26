// =============================================================================
// Alert rules for the cluster and the app
// =============================================================================
// One Prometheus rule group on the Azure Monitor workspace: Azure evaluates the PromQL itself, every
// minute, and fires into an action group that emails the owner. Dashboards show; these tell. The
// signals are the ones the dashboards in infra/dashboards chart, so a firing alert has a panel to
// open. Severity is Azure's scale: 0 critical, 1 error, 2 warning, 3 informational, 4 verbose.
// https://learn.microsoft.com/azure/azure-monitor/essentials/prometheus-rule-groups
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
    expression: 'max by (namespace, pod, container)(kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}) == 1'
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
    expression: 'kube_deployment_status_replicas_available < kube_deployment_spec_replicas'
    for: 'PT15M'
    severity: 2
    summary: 'A Deployment has had fewer available replicas than it wants for 15 minutes.'
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
    expression: '(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) > 0.85'
    for: 'PT15M'
    severity: 3
    summary: 'A node root filesystem is over 85% full.'
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
    expression: '(count(coredns_build_info) or vector(0)) < 1'
    for: 'PT5M'
    severity: 1
    summary: 'No CoreDNS pod is reporting: nothing in the cluster can resolve names.'
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
    alert: 'CertificateExpiringSoon'
    expression: '(min by (namespace, name)(certmanager_certificate_expiration_timestamp_seconds) - time()) / 86400 < 14'
    for: 'PT1H'
    severity: 2
    summary: 'A certificate expires in under 14 days: cert-manager should have renewed it about 30 days before, so renewal is failing.'
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
    expression: '(sum(envoy_server_live) or vector(0)) < 1'
    for: 'PT5M'
    severity: 1
    summary: 'No Envoy proxy is live: the public gateway is down.'
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
      actions: empty(alertEmail) ? [] : [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }]
  }
}

@description('The rule group')
output ruleGroupName string = ruleGroup.name

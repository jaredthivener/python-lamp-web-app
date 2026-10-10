// =============================================================================
// Cluster Schedule Module
// =============================================================================
// Two tiny Logic Apps: one starts the cluster each morning, one stops it each evening.
// Nodes are only billed while the cluster runs, and this is what keeps three of them
// inside the budget. Stopping keeps every Kubernetes object, so the cluster comes
// back as it was.
//
// To change the hours, change clusterStartTime / clusterStopTime and redeploy.
// To keep it up late one night, disable the "stop" Logic App in the portal, or just
// run `az aks start` again afterwards.
// =============================================================================

@description('The name of the AKS cluster to start and stop')
param clusterName string

@description('The Azure region where the Logic Apps will be deployed')
param location string

@description('Tags to apply to the resources')
param tags object = {}

@description('When the cluster starts each day, as HH:mm in timeZone')
param startTime string

@description('When the cluster stops each day, as HH:mm in timeZone')
param stopTime string

@description('Windows time zone name the times are in')
param timeZone string

var jobs = [
  { action: 'start', time: startTime }
  { action: 'stop', time: stopTime }
]

resource aks 'Microsoft.ContainerService/managedClusters@2026-06-01' existing = {
  name: clusterName
}

resource workflows 'Microsoft.Logic/workflows@2019-05-01' = [
  for job in jobs: {
    name: '${clusterName}-${job.action}'
    location: location
    tags: tags
    identity: {
      type: 'SystemAssigned'
    }
    properties: {
      state: 'Enabled'
      definition: {
        '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
        contentVersion: '1.0.0.0'
        triggers: {
          daily: {
            type: 'Recurrence'
            recurrence: {
              frequency: 'Day'
              interval: 1
              timeZone: timeZone
              // Without a start time a recurrence also fires the moment it is deployed,
              // which stopped a cluster that had only just been created.
              startTime: '2026-01-01T00:00:00'
              schedule: {
                hours: [int(split(job.time, ':')[0])]
                minutes: [int(split(job.time, ':')[1])]
              }
            }
          }
        }
        actions: {
          '${job.action}': {
            type: 'Http'
            inputs: {
              method: 'POST'
              uri: '${environment().resourceManager}${skip(aks.id, 1)}/${job.action}?api-version=${aks.apiVersion}'
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
        }
      }
    }
  }
]

// Starting and stopping is all these identities may do
resource workflowRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for (job, i) in jobs: {
    name: guid(aks.id, job.action, 'Azure Kubernetes Service Contributor Role')
    scope: aks
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ed7f3fbd-7b88-4dd4-9017-9adb7ce333f8') // Azure Kubernetes Service Contributor Role
      principalId: workflows[i].identity.principalId
      principalType: 'ServicePrincipal'
    }
  }
]

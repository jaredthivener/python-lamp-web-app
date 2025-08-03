// =============================================================================
// Azure Dashboard Module
// =============================================================================
// This module creates an Azure Dashboard for monitoring web application metrics
// including Application Insights data, App Service metrics, and PostgreSQL performance
// =============================================================================

@description('The name of the Azure Dashboard')
param dashboardName string

@description('The Azure region where the dashboard will be deployed')
param location string

@description('Tags to apply to the dashboard')
param tags object = {}

@description('The resource ID of the Application Insights instance')
param applicationInsightsId string

@description('The name of the Application Insights instance')
param applicationInsightsName string

@description('The resource ID of the App Service')
param appServiceId string

@description('The name of the App Service')
param appServiceName string

@description('The resource ID of the App Service Plan')
param appServicePlanId string

@description('The resource ID of the PostgreSQL Server')
param postgresServerId string

@description('The name of the PostgreSQL Server')
param postgresServerName string

// =============================================================================
// Azure Dashboard Resource
// =============================================================================
resource dashboard 'Microsoft.Portal/dashboards@2020-09-01-preview' = {
  name: dashboardName
  location: location
  tags: union(tags, {
    'hidden-title': 'Python LAMP Web App - Monitoring Dashboard'
  })
  properties: any({
    lenses: [
      {
        order: 0
        parts: [
          // Header/Overview Section
          {
            position: {
              x: 0
              y: 0
              rowSpan: 2
              colSpan: 12
            }
            metadata: {
              inputs: []
              type: 'Extension/HubsExtension/PartType/MarkdownPart'
              settings: {
                content: {
                  settings: {
                    content: '# 🐍 Python LAMP Web App Monitoring Dashboard\n\n**Application**: ${appServiceName} | **Insights**: ${applicationInsightsName} | **Database**: ${postgresServerName}\n\n---\n\n## Key Performance Indicators\n- 📈 **Request Volume**: Monitor incoming requests\n- ⚡ **Response Time**: Track application performance  \n- 🚨 **Error Rate**: Identify issues quickly\n- 💾 **Resource Usage**: CPU, Memory, Database health'
                    title: 'Dashboard Overview'
                  }
                }
              }
            }
          }

          // Application Insights - Server Requests
          {
            position: {
              x: 0
              y: 2
              rowSpan: 4
              colSpan: 4
            }
            metadata: {
              inputs: [
                {
                  name: 'options'
                  value: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: {
                            id: applicationInsightsId
                          }
                          name: 'requests/count'
                          aggregationType: 1
                          namespace: 'microsoft.insights/components'
                          metricVisualization: {
                            displayName: 'Server requests'
                            color: '#47BDF5'
                          }
                        }
                      ]
                      title: 'Server Requests'
                      titleKind: 1
                      visualization: {
                        chartType: 2
                        legendVisualization: {
                          isVisible: true
                          position: 2
                          hideSubtitle: false
                        }
                        axisVisualization: {
                          x: {
                            isVisible: true
                            axisType: 2
                          }
                          y: {
                            isVisible: true
                            axisType: 1
                          }
                        }
                      }
                      timespan: {
                        relative: {
                          duration: 86400000
                        }
                      }
                    }
                  }
                  isOptional: true
                }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              settings: {
                content: {
                  options: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: {
                            id: applicationInsightsId
                          }
                          name: 'requests/count'
                          aggregationType: 1
                          namespace: 'microsoft.insights/components'
                          metricVisualization: {
                            displayName: 'Requests'
                            color: '#47BDF5'
                          }
                        }
                      ]
                      title: 'Request Rate'
                      titleKind: 1
                      visualization: {
                        chartType: 2
                      }
                    }
                  }
                }
              }
            }
          }

          // Application Insights - Server Response Time
          {
            position: {
              x: 4
              y: 2
              rowSpan: 4
              colSpan: 4
            }
            metadata: {
              inputs: [
                {
                  name: 'options'
                  value: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: {
                            id: applicationInsightsId
                          }
                          name: 'requests/duration'
                          aggregationType: 4
                          namespace: 'microsoft.insights/components'
                          metricVisualization: {
                            displayName: 'Server response time'
                            color: '#7E58FF'
                          }
                        }
                      ]
                      title: 'Server Response Time'
                      titleKind: 1
                      visualization: {
                        chartType: 2
                      }
                      timespan: {
                        relative: {
                          duration: 86400000
                        }
                      }
                    }
                  }
                  isOptional: true
                }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              settings: {
                content: {
                  options: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: {
                            id: applicationInsightsId
                          }
                          name: 'requests/duration'
                          aggregationType: 4
                          namespace: 'microsoft.insights/components'
                          metricVisualization: {
                            displayName: 'Response Time'
                            color: '#7E58FF'
                          }
                        }
                      ]
                      title: 'Average Response Time'
                      titleKind: 1
                      visualization: {
                        chartType: 2
                      }
                    }
                  }
                }
              }
            }
          }

          // Application Insights - Failed Requests
          {
            position: {
              x: 8
              y: 2
              rowSpan: 4
              colSpan: 4
            }
            metadata: {
              inputs: [
                {
                  name: 'options'
                  value: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: {
                            id: applicationInsightsId
                          }
                          name: 'requests/failed'
                          aggregationType: 1
                          namespace: 'microsoft.insights/components'
                          metricVisualization: {
                            displayName: 'Failed requests'
                            color: '#EC008C'
                          }
                        }
                      ]
                      title: 'Failed Requests'
                      titleKind: 1
                      visualization: {
                        chartType: 2
                      }
                      timespan: {
                        relative: {
                          duration: 86400000
                        }
                      }
                    }
                  }
                  isOptional: true
                }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              settings: {
                content: {
                  options: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: {
                            id: applicationInsightsId
                          }
                          name: 'requests/failed'
                          aggregationType: 1
                          namespace: 'microsoft.insights/components'
                          metricVisualization: {
                            displayName: 'Failed Requests'
                            color: '#EC008C'
                          }
                        }
                      ]
                      title: 'Failed Requests'
                      titleKind: 1
                      visualization: {
                        chartType: 2
                      }
                    }
                  }
                }
              }
            }
          }

          // App Service - CPU Percentage
          {
            position: {
              x: 0
              y: 6
              rowSpan: 4
              colSpan: 4
            }
            metadata: {
              inputs: [
                {
                  name: 'options'
                  value: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: {
                            id: appServicePlanId
                          }
                          name: 'CpuPercentage'
                          aggregationType: 4
                          namespace: 'microsoft.web/serverfarms'
                          metricVisualization: {
                            displayName: 'CPU Percentage'
                            color: '#00BCF2'
                          }
                        }
                      ]
                      title: 'App Service CPU Usage'
                      titleKind: 1
                      visualization: {
                        chartType: 2
                      }
                      timespan: {
                        relative: {
                          duration: 86400000
                        }
                      }
                    }
                  }
                  isOptional: true
                }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
            }
          }

          // App Service - Memory Percentage
          {
            position: {
              x: 4
              y: 6
              rowSpan: 4
              colSpan: 4
            }
            metadata: {
              inputs: [
                {
                  name: 'options'
                  value: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: {
                            id: appServicePlanId
                          }
                          name: 'MemoryPercentage'
                          aggregationType: 4
                          namespace: 'microsoft.web/serverfarms'
                          metricVisualization: {
                            displayName: 'Memory Percentage'
                            color: '#0078D4'
                          }
                        }
                      ]
                      title: 'App Service Memory Usage'
                      titleKind: 1
                      visualization: {
                        chartType: 2
                      }
                      timespan: {
                        relative: {
                          duration: 86400000
                        }
                      }
                    }
                  }
                  isOptional: true
                }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
            }
          }

          // PostgreSQL - Active Connections
          {
            position: {
              x: 8
              y: 6
              rowSpan: 4
              colSpan: 4
            }
            metadata: {
              inputs: [
                {
                  name: 'options'
                  value: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: {
                            id: postgresServerId
                          }
                          name: 'active_connections'
                          aggregationType: 4
                          namespace: 'microsoft.dbforpostgresql/flexibleservers'
                          metricVisualization: {
                            displayName: 'Active Connections'
                            color: '#FF8C00'
                          }
                        }
                      ]
                      title: 'PostgreSQL Active Connections'
                      titleKind: 1
                      visualization: {
                        chartType: 2
                      }
                      timespan: {
                        relative: {
                          duration: 86400000
                        }
                      }
                    }
                  }
                  isOptional: true
                }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              settings: {
                content: {
                  options: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: {
                            id: postgresServerId
                          }
                          name: 'active_connections'
                          aggregationType: 4
                          namespace: 'microsoft.dbforpostgresql/flexibleservers'
                          metricVisualization: {
                            displayName: 'Active Connections'
                            color: '#FF8C00'
                          }
                        }
                      ]
                      title: 'DB Connections'
                      titleKind: 1
                      visualization: {
                        chartType: 2
                      }
                    }
                  }
                }
              }
            }
          }

          // App Service - HTTP Response Codes
          {
            position: {
              x: 0
              y: 10
              rowSpan: 4
              colSpan: 6
            }
            metadata: {
              inputs: [
                {
                  name: 'options'
                  value: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: {
                            id: appServiceId
                          }
                          name: 'Http2xx'
                          aggregationType: 1
                          namespace: 'microsoft.web/sites'
                          metricVisualization: {
                            displayName: 'Http 2xx'
                            color: '#00A400'
                          }
                        }
                        {
                          resourceMetadata: {
                            id: appServiceId
                          }
                          name: 'Http4xx'
                          aggregationType: 1
                          namespace: 'microsoft.web/sites'
                          metricVisualization: {
                            displayName: 'Http 4xx'
                            color: '#FF8C00'
                          }
                        }
                        {
                          resourceMetadata: {
                            id: appServiceId
                          }
                          name: 'Http5xx'
                          aggregationType: 1
                          namespace: 'microsoft.web/sites'
                          metricVisualization: {
                            displayName: 'Http 5xx'
                            color: '#EC008C'
                          }
                        }
                      ]
                      title: 'HTTP Response Codes'
                      titleKind: 1
                      visualization: {
                        chartType: 2
                      }
                      timespan: {
                        relative: {
                          duration: 86400000
                        }
                      }
                    }
                  }
                  isOptional: true
                }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              settings: {
                content: {
                  options: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: {
                            id: appServiceId
                          }
                          name: 'Http2xx'
                          aggregationType: 1
                          namespace: 'microsoft.web/sites'
                          metricVisualization: {
                            displayName: 'Http 2xx'
                            color: '#00A400'
                          }
                        }
                        {
                          resourceMetadata: {
                            id: appServiceId
                          }
                          name: 'Http4xx'
                          aggregationType: 1
                          namespace: 'microsoft.web/sites'
                          metricVisualization: {
                            displayName: 'Http 4xx'
                            color: '#FF8C00'
                          }
                        }
                        {
                          resourceMetadata: {
                            id: appServiceId
                          }
                          name: 'Http5xx'
                          aggregationType: 1
                          namespace: 'microsoft.web/sites'
                          metricVisualization: {
                            displayName: 'Http 5xx'
                            color: '#EC008C'
                          }
                        }
                      ]
                      title: 'HTTP Status Codes'
                      titleKind: 1
                      visualization: {
                        chartType: 2
                      }
                    }
                  }
                }
              }
            }
          }

          // PostgreSQL - CPU & Memory Usage
          {
            position: {
              x: 6
              y: 10
              rowSpan: 4
              colSpan: 6
            }
            metadata: {
              inputs: [
                {
                  name: 'options'
                  value: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: {
                            id: postgresServerId
                          }
                          name: 'cpu_percent'
                          aggregationType: 4
                          namespace: 'microsoft.dbforpostgresql/flexibleservers'
                          metricVisualization: {
                            displayName: 'CPU percent'
                            color: '#B146C2'
                          }
                        }
                        {
                          resourceMetadata: {
                            id: postgresServerId
                          }
                          name: 'memory_percent'
                          aggregationType: 4
                          namespace: 'microsoft.dbforpostgresql/flexibleservers'
                          metricVisualization: {
                            displayName: 'Memory percent'
                            color: '#FF6347'
                          }
                        }
                      ]
                      title: 'PostgreSQL Resource Usage'
                      titleKind: 1
                      visualization: {
                        chartType: 2
                      }
                      timespan: {
                        relative: {
                          duration: 86400000
                        }
                      }
                    }
                  }
                  isOptional: true
                }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
            }
          }
        ]
      }
    ]
    metadata: {
      model: {
        timeRange: {
          value: {
            relative: {
              duration: 24
              timeUnit: 1
            }
          }
          type: 'MsPortalFx.Composition.Configuration.ValueTypes.TimeRange'
        }
        filterLocale: {
          value: 'en-us'
        }
        filters: {
          value: {
            MsPortalFx_TimeRange: {
              model: {
                format: 'utc'
                granularity: 'auto'
                relative: '24h'
              }
              displayCache: {
                name: 'UTC Time'
                value: 'Past 24 hours'
              }
              filteredPartIds: []
            }
          }
        }
      }
    }
  })
}

// =============================================================================
// Outputs
// =============================================================================
@description('The name of the Azure Dashboard')
output dashboardName string = dashboard.name

@description('The resource ID of the Azure Dashboard')
output dashboardId string = dashboard.id

@description('The URL to access the dashboard in the Azure portal')
output dashboardUrl string = 'https://portal.azure.com/#@/dashboard/arm${dashboard.id}'

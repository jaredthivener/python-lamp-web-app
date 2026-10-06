using './main.bicep'

// =============================================================================
// Azure Infrastructure Parameters for Lamp Web App
// =============================================================================
// Sized for a $150/month credit: three small Arm64 (Cobalt) nodes that run 8 hours a
// day come to roughly $120 with everything else. See infra/README.md for the sums.
// =============================================================================

// Environment Configuration
param environmentName = 'dev'
param location = 'westus3' // East US 2 costs the same but refuses PostgreSQL flexible servers on a credit subscription
param resourceGroupName = 'rg-lamp-web-app-dev'

// Who may run kubectl against the cluster: your Entra object ID
// (az ad signed-in-user show --query id -o tsv). The deploy workflow takes it from the
// repository secret of the same name; for a local run, `azd env set AKS_ADMIN_OBJECT_ID <id>`.
// Left empty, nobody is granted access (an Owner can still assign the role later).
param clusterAdminObjectId = readEnvironmentVariable('AKS_ADMIN_OBJECT_ID', '')

// Running hours. Each extra hour a day adds about $8 a month, and the spending limit on
// a credit subscription switches everything off once the month's credit is gone.
param clusterStartTime = '09:00'
param clusterStopTime = '17:00'
param scheduleTimeZone = 'Eastern Standard Time'

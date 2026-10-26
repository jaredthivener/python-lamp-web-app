using './main.bicep'

// =============================================================================
// Azure Infrastructure Parameters for Lamp Web App
// =============================================================================
// Sized for a $150/month credit: three small Arm64 (Cobalt) nodes that run 8 hours a
// day come to roughly $130 with everything else. See infra/README.md for the sums.
// =============================================================================

// Environment Configuration
param environmentName = 'dev'
param location = 'centralus' // a credit subscription is refused Burstable PostgreSQL flexible servers in West US 3 (and all of them in East US 2); see infra/README.md
param resourceGroupName = 'rg-lamp-web-app-dev'

// Who may run kubectl against the cluster: your Entra object ID
// (az ad signed-in-user show --query id -o tsv). The deploy workflow takes it from the
// repository secret of the same name; for a local run, `azd env set AKS_ADMIN_OBJECT_ID <id>`.
// Left empty, nobody is granted access (an Owner can still assign the role later).
param clusterAdminObjectId = readEnvironmentVariable('AKS_ADMIN_OBJECT_ID', '')

// Where alerts are emailed: the repository secret of the same name (azd reads it from the environment). Left
// empty, the alert rules are still created and still fire, and show in the portal under Alerts.
param alertEmail = readEnvironmentVariable('ALERT_EMAIL', '')

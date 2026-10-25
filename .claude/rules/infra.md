---
paths:
  - "infra/**"
  - "azure.yaml"
---

# Infrastructure (Bicep)

- Check: `az bicep build --file infra/main.bicep --stdout > /dev/null && az bicep lint --file infra/main.bicep`. A hook builds each `.bicep` file you edit. BCP081 ("does not have types available") is expected for the API versions infra/README.md lists.
- `az deployment sub validate --location centralus --parameters infra/main.bicepparam` is the authority on whether ARM accepts the template. The Infrastructure checks workflow runs it, and a what-if, on every pull request that touches `infra/`.
- API versions: the newest GA version that ARM accepts and the Bicep type data covers. List them with `az provider show -n <namespace> --query "resourceTypes[?resourceType=='<type>'].apiVersions"`; a BCP081 on that version means it has no type data yet. Preview only where no GA version has the property needed.
- Use an Azure Verified Module (`br/public:avm/res/...`) where one exists and supports what is needed. Their defaults lean towards production, so write the cost choices out in the call.
- Keep AVM pins current against the [AVM Bicep resource module index](https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/), which lists each module's status and current version. Its data is `modules.json` on the same site; this compares every pin under `infra/` with it:

  ```bash
  curl -s https://azure.github.io/Azure-Verified-Modules/module-indexes/v1/modules.json |
    jq -r --arg pins "$(grep -rhoE 'br/public:avm/[a-z0-9/-]+:[0-9.]+' infra | sort -u)" '
      [.modules[][][]? | select(.ecosystem == "bicep") | {key: .moduleName, value: .}] | from_entries as $idx
      | $pins | split("\n")[] | sub("^br/public:"; "") | split(":") as [$m, $p] | $idx[$m]
      | "\($m) pinned \($p), current \(.registry.currentVersion), \(.moduleStatus)\(if .registry.currentVersion != $p then "  <- differs" else "" end)"'
  ```

  Before moving a pin, read the module's `CHANGELOG.md` (in `https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/<module>`) for breaking changes. The pull request's what-if shows what the new version would change in Azure.
- Not on AVM, checked 2026-10-11 against the index's current versions: the AKS cluster (`avm/res/container-service/managed-cluster` 0.14.0 uses API 2025-10-01 and has no `appMonitoring`) and Application Insights (`avm/res/insights/component` 0.8.0 uses API 2020-02-02 and has no `AzureMonitorWorkspaceIngestionMode`, which the OTLP setup needs). Look again when either's current version changes.
- A deployment never deletes a resource the Bicep stopped declaring. Delete it, and its role assignments, by hand as part of the same change.
- The subscription is an MSDN credit with a hard $150 monthly spending limit: no spot VMs, and PostgreSQL flexible servers are refused in East US 2 and several other regions, and Burstable ones in West US 3, hence centralus. `list-skus` does not show the refusal: creating a server does. Update the cost table in infra/README.md with any change that affects cost.
- Not wanted in this environment: authorized IP ranges, Defender for Containers, control-plane diagnostic settings, start/stop schedules.
- Values the manifests need reach Flux through `manifestValues` in `infra/main.bicep`; see the k8s rule.

---
paths:
  - "infra/**"
  - "azure.yaml"
---

# Infrastructure (Bicep)

- Check: `az bicep build --file infra/main.bicep --stdout > /dev/null && az bicep lint --file infra/main.bicep`. A hook builds each `.bicep` file you edit. BCP081 ("does not have types available") is expected for the API versions infra/README.md lists.
- `az deployment sub validate --location westus3 --parameters infra/main.bicepparam` is the authority on whether ARM accepts the template. The Infrastructure checks workflow runs it, and a what-if, on every pull request that touches `infra/`.
- API versions: the newest GA version that ARM accepts and the Bicep type data covers. List them with `az provider show -n <namespace> --query "resourceTypes[?resourceType=='<type>'].apiVersions"`; a BCP081 on that version means it has no type data yet. Preview only where no GA version has the property needed.
- Use an Azure Verified Module (`br/public:avm/res/...`) where one exists and supports what is needed. Their defaults lean towards production, so write the cost choices out in the call. Newest version: `curl -s https://mcr.microsoft.com/v2/bicep/avm/res/<module>/tags/list`, sorted as versions (the list comes back sorted as text).
- A deployment never deletes a resource the Bicep stopped declaring. Delete it, and its role assignments, by hand as part of the same change.
- The subscription is an MSDN credit with a hard $150 monthly spending limit: no spot VMs, and PostgreSQL flexible servers are refused in East US 2 and several other regions, hence westus3. Update the cost table in infra/README.md with any change that affects cost.
- Not wanted in this environment: authorized IP ranges, Defender for Containers, control-plane diagnostic settings, start/stop schedules.
- Values the manifests need reach Flux through `manifestValues` in `infra/main.bicep`; see the k8s rule.

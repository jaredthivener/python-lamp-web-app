#!/usr/bin/env bash
# Checks the OpenTelemetry collector's configuration the way the cluster will use it: rendered by
# Flux with the placeholder values, then validated by the collector image pinned in
# k8s/observability/otel-gateway.yaml. A new collector version that no longer accepts the config
# (azure_auth's syntax changed in 0.148) fails here, on the pull request, and not on the cluster.
#   .github/scripts/validate-collector.sh path/to/values.env
set -euo pipefail

values=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

{
  cat <<'YAML'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: {name: observability, namespace: flux-system}
spec:
  interval: 1m
  path: ./k8s/observability
  prune: true
  sourceRef: {kind: OCIRepository, name: lamp}
  postBuild:
    substitute:
YAML
  sed -E 's/^([A-Za-z_]+)=(.*)$/      \1: "\2"/' "$values"
} > "$work/kustomization.yaml"

flux build kustomization observability --path k8s/observability \
  --kustomization-file "$work/kustomization.yaml" --dry-run > "$work/rendered.yaml"

python3 - "$work" <<'PY'
import sys
import yaml

work = sys.argv[1]
docs = [d for d in yaml.safe_load_all(open(f"{work}/rendered.yaml")) if d]
config = next(d for d in docs if d["kind"] == "ConfigMap")["data"]["config.yaml"]
open(f"{work}/config.yaml", "w").write(config)
PY

image=$(grep -oE 'ghcr\.io/open-telemetry/[^[:space:]]+' k8s/observability/otel-gateway.yaml | head -1)
# The three AZURE_* variables are what AKS's workload identity webhook sets in the pod
docker run --rm \
  -e AZURE_CLIENT_ID=00000000-0000-0000-0000-000000000000 \
  -e AZURE_TENANT_ID=00000000-0000-0000-0000-000000000000 \
  -e AZURE_FEDERATED_TOKEN_FILE=/var/run/secrets/azure/tokens/azure-identity-token \
  -v "$work/config.yaml:/conf/config.yaml:ro" \
  "$image" validate --config=/conf/config.yaml
echo "The collector accepts its configuration ($image)"

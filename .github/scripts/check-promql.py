"""Checks that every PromQL expression in the Grafana dashboards parses, using Prometheus's own promtool.

A typo in a query otherwise shows up as an empty panel on the cluster, and a syntax error in an alert
rule (infra/modules/monitor/alerts.bicep) only when Azure rejects the deployment. This does not run the
queries: whether the metrics exist is checked against the live workspace (see infra/README.md).

    python3 .github/scripts/check-promql.py            # needs Docker
"""

import json
import pathlib
import re
import subprocess
import sys
import tempfile

# ponytail: pinned here, not in a Dockerfile, so Dependabot does not see it: bump it by hand with the
# Prometheus release. Quoted metric names ({"http.server.request.duration"}) need Prometheus 3.
PROMETHEUS = "prom/prometheus:v3.15.1@sha256:fa3302279710be2f21a8301ec17a8b4f2301fd829bd113839b3b6b02b6f191a2"

# Grafana's own variables, replaced with plausible values so the expression parses
GRAFANA_VARIABLES = {
    "$__rate_interval": "5m",
    "$__interval_ms": "60000",
    "$__interval": "1m",
    "$__range_s": "3600",
    "$__range": "1h",
}

root = pathlib.Path(__file__).resolve().parents[2]
rules = []
for dashboard in sorted((root / "infra/dashboards").glob("*.json")):
    for panel in json.loads(dashboard.read_text()).get("panels", []):
        for target in panel.get("targets", []):
            expr = target["expr"]
            for variable, value in GRAFANA_VARIABLES.items():
                expr = expr.replace(variable, value)
            rules.append((f"{dashboard.name}: {panel['title']}", expr))

# The alert rules' expressions, written in alerts.bicep as expression: '...' lines
alerts = root / "infra/modules/monitor/alerts.bicep"
if alerts.exists():
    for name, expr in re.findall(r"alert: '([^']+)'\s+expression: '((?:[^'\\]|\\.|'')*)'", alerts.read_text()):
        rules.append((f"alerts.bicep: {name}", expr.replace("''", "'")))

with tempfile.TemporaryDirectory(dir=root / "scratch" if (root / "scratch").is_dir() else None) as work:
    lines = ["groups:", "  - name: check", "    rules:"]
    for index, (_, expr) in enumerate(rules):
        lines += [f"      - record: check:{index}", f"        expr: {json.dumps(expr)}"]
    pathlib.Path(work, "rules.yaml").write_text("\n".join(lines) + "\n")
    result = subprocess.run(
        ["docker", "run", "--rm", "-v", f"{work}:/work:ro", "--entrypoint", "promtool", PROMETHEUS, "check", "rules", "/work/rules.yaml"],
        capture_output=True,
        text=True,
    )

print(f"{len(rules)} expressions checked")
if result.returncode:
    print(result.stdout + result.stderr)
    # promtool names the rule by its position; say which panel or alert that was
    for index in sorted({int(i) for i in re.findall(r"check:(\d+)", result.stdout + result.stderr)}):
        print(f"  check:{index} is {rules[index][0]}")
    sys.exit(1)
print("All parse")

---
name: deploy-infra
description: Deploy the Azure infrastructure from main with the Deploy Azure Infrastructure workflow, wait for it, then verify the live environment
disable-model-invocation: true
argument-hint: "[environment, default dev]"
allowed-tools:
  - Bash(git fetch *)
  - Bash(git log *)
  - Bash(gh run list *)
  - Bash(gh run view *)
  - Bash(gh run watch *)
  - Bash(gh workflow run *)
---

## Context

- `main` on GitHub: !`git fetch -q origin main && git log -1 --format='%h %s (%cr)' origin/main`
- Recent infrastructure runs: !`gh run list --limit 8 --json workflowName,databaseId,status,conclusion,headSha --jq '.[] | select(.workflowName | endswith("Azure Infrastructure")) | "\(.workflowName) \(.databaseId) \(.status) \(.conclusion) \(.headSha[0:7])"'`

## Steps

Environment: `$ARGUMENTS` (use `dev` if that is empty).

1. If a Deploy or Destroy run above is still `queued`, `waiting` or `in_progress`, stop and report it. The two share a concurrency group, so a new run would only queue behind it.
2. Start the run from `main`, the only branch the environment accepts:
   `gh workflow run "Deploy Azure Infrastructure" --ref main -f environment=<environment>`
3. Find it with `gh run list --workflow "Deploy Azure Infrastructure" --limit 1 --json databaseId,status,headSha,url`, and check that its `headSha` is the `main` commit above.
4. `waiting` means it needs Jared to approve the environment. Tell him once, with the run's URL, and wait. That approval is the only step that is his; check the run's status yourself.
5. Watch it in the background: `gh run watch <id> --exit-status` with `run_in_background`. A first deploy takes about 20 minutes, a repeat about 10.
6. If it fails, read `gh run view <id> --log-failed` and report the failing step and its error line. The deploy step already makes three attempts, a minute apart, for the PostgreSQL "subnet doesn't exist" error, so a failure there survived all three.
7. If it succeeds, run the `verify-live` skill for the same environment and report its results.

---
paths:
  - ".github/**"
---

# GitHub Actions

- Pin every third-party action to a full commit SHA with its version in a comment (`uses: actions/checkout@<sha> # v7`). Dependabot keeps them current; a new composite action directory must be added to `directories` in `.github/dependabot.yml`.
- Jobs that touch Azure log in with OIDC and run under the `dev` environment, whose required reviewer is the gate. Deploy and Destroy share a concurrency group and never cancel each other.
- Long-running `az` commands sometimes crash on the runners before sending anything (https://github.com/Azure/azure-cli/issues/33996). Use `--no-wait` with a polling loop, or `az rest`, as `infra-destroy.yml` does.
- Run a new step against something real before the pull request: a scratch resource group, or `gh workflow run <file> --ref <branch>` for workflows with `workflow_dispatch`.

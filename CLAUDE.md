# Lamp

One lamp shared live by everyone with the page open: FastAPI with Server-Sent Events, Postgres (SQLite locally), and a WebGL page with no build step. It runs on AKS, where Flux applies what CI publishes from `main`. README.md and infra/README.md are the documentation of record: read the part you are changing, and update it in the same pull request.

Rules for `infra/`, `k8s/` and `.github/` are in `.claude/rules/` and load when you touch those files.

## Commands

- `uv run pytest`: the API and store tests, on SQLite. CI runs them again on Postgres with `TEST_DATABASE_URL=postgresql+psycopg2://postgres:postgres@localhost:5432/postgres`
- `npm test`: the lamp physics tests (`node --test`, no install needed)
- `uv run mypy src`: passes today. CI does not run it, so run it after changing Python
- `uv run black src tests`: a hook already runs black on every Python file you edit
- `./start.sh`: the app on port 8000, with its SQLite file at `$TMPDIR/lamp.db`. Jared's own dev server usually holds both, so run yours with a high `PORT` and a scratch `TMPDIR`

## How work reaches `main`

- Branch from an up-to-date `origin/main` and open a pull request. `main` requires the Tests check.
- Jared merges pull requests himself, often without saying so. Run `gh pr view <n> --json state` before pushing to an existing branch; if it merged, branch again from `origin/main`. Never merge one yourself (`gh pr merge` is denied in `.claude/settings.json`).
- Merging deploys the app (CI publishes, Flux applies) but not the infrastructure. `/deploy-infra` runs the Deploy workflow, which waits for Jared to approve the `dev` environment. Trigger runs and watch their status yourself with `gh`; don't ask Jared to check.
- The environment exists only while Jared is testing: he deploys it on demand and runs the Destroy workflow himself when done. Nothing starts or stops it on a schedule.

## Standards

- Ground every claim about Azure, Flux, Kubernetes or Claude Code in that tool's own docs, CRDs or APIs, and cite them: Microsoft Learn (the `microsoft-learn` MCP server, or WebFetch on learn.microsoft.com) for Azure, fluxcd.io and the controller specs for Flux. Say which parts are documented, which you measured, and which are your inference.
- Follow the documented approach. When budget or the subscription forces a departure, say so before building it, and record it in the "Not followed, and why" tables in infra/README.md.
- Use Flux as its current docs describe; don't work around its behaviour.
- Test a doc-derived claim before writing it into code or a comment, and run a new workflow step against something real before the pull request. Report what was not tested as not tested.
- Mark a deliberate shortcut with a `ponytail:` comment naming its ceiling and the upgrade path, as `src/main.py` does.
- Read live state before explaining a failure, and reproduce a bug before fixing it.

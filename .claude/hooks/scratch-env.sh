#!/bin/bash
# SessionStart hook: points TMPDIR at scratch/tmp for every Bash command Claude runs, so
# mktemp, pytest's tmp_path and the app's SQLite file land in the project, not the system
# temp directory. Project settings can't set TMPDIR in "env"; CLAUDE_ENV_FILE is the
# documented way to export variables to later Bash commands.
# https://code.claude.com/docs/en/hooks#persist-environment-variables
mkdir -p "$CLAUDE_PROJECT_DIR/scratch/tmp"
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo "export TMPDIR=\"$CLAUDE_PROJECT_DIR/scratch/tmp\"" >> "$CLAUDE_ENV_FILE"
fi
exit 0

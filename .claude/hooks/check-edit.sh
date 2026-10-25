#!/bin/bash
# PostToolUse hook for Edit and Write: formats a Python file with black and builds a Bicep
# file, so a mistake shows up on the edit that made it. Exit code 2 shows stderr to Claude.
# https://code.claude.com/docs/en/hooks
file=$(jq -r '.tool_input.file_path // empty')

case "$file" in
  "$CLAUDE_PROJECT_DIR"/*.py)
    out=$(cd "$CLAUDE_PROJECT_DIR" && uv run --quiet black --quiet "$file" 2>&1) || {
      echo "black failed on $file: $out" >&2
      exit 2
    }
    ;;
  "$CLAUDE_PROJECT_DIR"/*.bicep)
    out=$(az bicep build --file "$file" --stdout 2>&1 >/dev/null) || {
      echo "az bicep build failed on $file:" >&2
      grep -v -e 'New Azure CLI version' -e 'auto upgrade' <<<"$out" >&2
      exit 2
    }
    ;;
esac
exit 0

#!/bin/bash
# PreToolUse hook: temporary files belong in scratch/, where Jared can open them. Denies file
# writes under the system temp directories, and asks before a Bash command that names one
# (the command text can't tell a read from a write). Runs in subagents too.
# https://code.claude.com/docs/en/hooks#pretooluse-decision-control
input=$(cat)
tool=$(jq -r '.tool_name' <<<"$input")
temp='(^|[[:space:]"'"'"'=:(])(/private)?(/tmp|/var/tmp|/var/folders)([/[:space:]"'"'"')]|$)'

decide() {
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
}

case "$tool" in
  Write | Edit | NotebookEdit)
    path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
    if grep -Eq "$temp" <<<"$path"; then
      decide deny "$path is in a system temp directory. This project keeps temporary files in $CLAUDE_PROJECT_DIR/scratch/ (gitignored); write it there."
    fi
    ;;
  Bash)
    if jq -r '.tool_input.command' <<<"$input" | grep -Eq "$temp"; then
      decide ask "The command names a system temp directory. This project keeps temporary files in scratch/; \$TMPDIR already points at scratch/tmp."
    fi
    ;;
esac
exit 0

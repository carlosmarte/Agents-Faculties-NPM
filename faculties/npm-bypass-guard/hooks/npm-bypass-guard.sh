#!/usr/bin/env bash
# PreToolUse hook (Bash, Write, Edit): blocks attempts to switch off or weaken npm audit.
# The project .npmrc guardrail cannot stop command-line flags or environment variables;
# this hook does.
set -euo pipefail
shopt -s nocasematch

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT")

block() {
  {
    echo "BLOCKED by npm-bypass-guard: $1"
    echo "Audits must stay on at audit-level=low. Fix or replace the vulnerable dependency instead of bypassing the gate; if a bypass is truly needed, ask the user to run it."
  } >&2
  exit 2
}

WEAK_LINE='^[[:space:]]*(audit[[:space:]]*=[[:space:]]*(false|0)|audit-level[[:space:]]*=[[:space:]]*(moderate|high|critical|none))[[:space:]]*$'
HAS_AUDIT='^[[:space:]]*audit[[:space:]]*=[[:space:]]*true[[:space:]]*$'
HAS_LEVEL='^[[:space:]]*audit-level[[:space:]]*=[[:space:]]*low[[:space:]]*$'

case "$TOOL" in
  Bash)
    CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
    [[ "$CMD" =~ (npm|npx|npmrc) ]] || exit 0

    RE_NO_AUDIT='--no-audit|--audit[=[:space:]]+(false|0)'
    RE_ENV='npm_config_audit'
    RE_ASSIGN='(^|[^a-z-])audit[[:space:]]*[=[:space:]][[:space:]]*(false|0)([^a-z0-9]|$)'
    RE_LEVEL='audit-level[=[:space:]]+(moderate|high|critical|none)'
    RE_DELETE='npm[[:space:]]+(config|c)[[:space:]]+(delete|rm)[[:space:]]+audit'
    RE_FORCE='npm[^;&|]*[[:space:]](--force|-f)([[:space:]]|$)'

    [[ "$CMD" =~ $RE_NO_AUDIT ]] && block "the command disables npm audit (--no-audit / --audit=false)."
    [[ "$CMD" =~ $RE_ENV ]] && block "the command sets an npm_config_audit* environment variable, which overrides the project .npmrc."
    [[ "$CMD" =~ $RE_ASSIGN ]] && block "the command sets audit=false."
    [[ "$CMD" =~ $RE_LEVEL ]] && block "the command raises audit-level above low."
    [[ "$CMD" =~ $RE_DELETE ]] && block "the command deletes the audit setting."
    [[ "$CMD" =~ $RE_FORCE ]] && block "the command runs npm with --force, which overrides safety checks and can install breaking or vulnerable versions."
    exit 0
    ;;
  Write | Edit)
    FILE=$(jq -r '.tool_input.file_path // empty' <<<"$INPUT")
    [[ "$(basename "$FILE")" == ".npmrc" ]] || exit 0
    if [[ "$TOOL" == "Write" ]]; then
      NEW=$(jq -r '.tool_input.content // empty' <<<"$INPUT")
      grep -Eiq "$WEAK_LINE" <<<"$NEW" && block "the new .npmrc disables audits or raises audit-level."
      grep -Eq "$HAS_AUDIT" <<<"$NEW" || block "the new .npmrc is missing audit=true."
      grep -Eq "$HAS_LEVEL" <<<"$NEW" || block "the new .npmrc is missing audit-level=low."
    else
      OLD=$(jq -r '.tool_input.old_string // empty' <<<"$INPUT")
      NEW=$(jq -r '.tool_input.new_string // empty' <<<"$INPUT")
      grep -Eiq "$WEAK_LINE" <<<"$NEW" && block "the edit disables audits or raises audit-level in .npmrc."
      if grep -Eq "$HAS_AUDIT" <<<"$OLD" && ! grep -Eq "$HAS_AUDIT" <<<"$NEW"; then
        block "the edit removes audit=true from .npmrc."
      fi
      if grep -Eq "$HAS_LEVEL" <<<"$OLD" && ! grep -Eq "$HAS_LEVEL" <<<"$NEW"; then
        block "the edit removes audit-level=low from .npmrc."
      fi
    fi
    exit 0
    ;;
esac
exit 0

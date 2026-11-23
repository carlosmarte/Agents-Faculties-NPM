#!/usr/bin/env bash
# PreToolUse hook (Bash, Write, Edit): dependency lifecycle scripts (preinstall, install,
# postinstall) may only run for packages a human has approved.
#   - blocks installs unless the project enforces a script policy
#     (strict-allow-scripts=true, or ignore-scripts=true on npm versions without allowScripts)
#   - blocks flags, environment variables and config changes that bypass the policy
#   - asks the user before anything that approves a package's scripts
set -euo pipefail
shopt -s nocasematch

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT")
CWD=$(jq -r '.cwd // empty' <<<"$INPUT")
[[ -n "$CWD" && -d "$CWD" ]] && cd "$CWD"

block() {
  {
    echo "BLOCKED by npm-install-scripts-guard: $1"
    echo "Unreviewed install scripts must not run. Deny the package's scripts with 'npm install-scripts deny <pkg>', or ask the user to review and approve it."
  } >&2
  exit 2
}

ask() {
  jq -n --arg r "npm-install-scripts-guard: $1" '{hookSpecificOutput: {hookEventName: "PreToolUse",
    permissionDecision: "ask", permissionDecisionReason: $r}}'
  exit 0
}

if [[ "$TOOL" == "Write" || "$TOOL" == "Edit" ]]; then
  FILE=$(jq -r '.tool_input.file_path // empty' <<<"$INPUT")
  NEW=$(jq -r '.tool_input.content // .tool_input.new_string // empty' <<<"$INPUT")
  if [[ "$(basename "$FILE")" == "package.json" && "$NEW" == *allowScripts* ]]; then
    ask "this change touches allowScripts in package.json, which decides which packages may run install scripts on this machine. Approve only if you have reviewed them."
  fi
  exit 0
fi

[[ "$TOOL" == "Bash" ]] || exit 0
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
[[ "$CMD" =~ npm ]] || exit 0

RE_BYPASS='--dangerously-allow-all-scripts|--allow-scripts([=[:space:]]|$)|--no-strict-allow-scripts|--no-ignore-scripts|--(strict-allow|ignore)-scripts[=[:space:]]+(false|0)|npm_config_(dangerously_allow_all|allow|strict_allow|ignore)_scripts|(dangerously-allow-all-scripts|allow-scripts)[[:space:]]*[=[:space:]]|(strict-allow|ignore)-scripts[[:space:]]*=[[:space:]]*(false|0)'
RE_APPROVE='npm[[:space:]]+(install-scripts[[:space:]]+approve|approve-scripts)([[:space:]]|$)'
RE_INSTALL='npm[[:space:]]+(install|i|add|ci|update|up|upgrade|rebuild|install-test|it|install-ci-test|cit|dedupe)([[:space:]]|$)'
RE_FLAG_ON='--ignore-scripts([[:space:]]|=true|$)'

[[ "$CMD" =~ $RE_BYPASS ]] && block "the command bypasses or weakens the install-script policy."
[[ "$CMD" =~ $RE_APPROVE ]] && ask "this command approves install scripts, letting those packages run code on this machine at install time. Approve only if you have reviewed them."

if [[ "$CMD" =~ $RE_INSTALL ]] && ! [[ "$CMD" =~ $RE_FLAG_ON ]]; then
  CONFIG=$(npm config get strict-allow-scripts dangerously-allow-all-scripts ignore-scripts 2>/dev/null || true)
  grep -qx 'ignore-scripts=true' <<<"$CONFIG" && exit 0
  if grep -qx 'strict-allow-scripts=true' <<<"$CONFIG" && ! grep -qx 'dangerously-allow-all-scripts=true' <<<"$CONFIG"; then
    exit 0
  fi
  block "this project has no enforced install-script policy, so the install would run third-party scripts unreviewed. Add strict-allow-scripts=true to the project .npmrc first (ignore-scripts=true if this npm does not support it)."
fi
exit 0

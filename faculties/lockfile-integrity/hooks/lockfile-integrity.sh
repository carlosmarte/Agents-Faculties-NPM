#!/usr/bin/env bash
# Register for both events:
#   PreToolUse  (Bash|Write|Edit): blocks hand-edits of the lockfile and commands that skip it
#   PostToolUse (Bash): after a command that changes dependencies, verifies the lockfile
set -euo pipefail

INPUT=$(cat)
EVENT=$(jq -r '.hook_event_name // empty' <<<"$INPUT")
TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT")
CWD=$(jq -r '.cwd // empty' <<<"$INPUT")
HERE=$(cd "$(dirname "$0")" && pwd)
[[ -n "$CWD" && -d "$CWD" ]] && cd "$CWD"

block() {
  echo "BLOCKED by lockfile-integrity: $1" >&2
  exit 2
}

if [[ "$TOOL" == "Write" || "$TOOL" == "Edit" ]]; then
  FILE=$(jq -r '.tool_input.file_path // empty' <<<"$INPUT")
  case "$(basename "$FILE")" in
    package-lock.json | npm-shrinkwrap.json)
      block "do not edit the lockfile by hand. Change package.json or run an npm command and let npm regenerate it."
      ;;
  esac
  exit 0
fi

[[ "$TOOL" == "Bash" ]] || exit 0
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
[[ "$CMD" =~ npm ]] || exit 0

if [[ "$EVENT" == "PreToolUse" ]]; then
  RE_SKIP='--no-package-lock|--package-lock[=[:space:]]+(false|0)|npm_config_package_lock|package-lock[[:space:]]*=[[:space:]]*(false|0)'
  [[ "$CMD" =~ $RE_SKIP ]] && block "the command disables the lockfile. Installs must read and update package-lock.json."
  exit 0
fi

RE_CHANGES='npm[[:space:]]+(install|i|add|ci|update|up|upgrade|uninstall|remove|rm|un|dedupe|audit[[:space:]]+fix)([[:space:]]|$)'
if [[ "$CMD" =~ $RE_CHANGES && -f package.json ]]; then
  if ! OUT=$("$HERE/../scripts/lockfile-check.sh" 2>&1); then
    {
      echo "BLOCKED by lockfile-integrity after running: $CMD"
      echo "$OUT"
      echo "Action required: remove or replace dependencies that resolve from git, plain HTTP or an unexpected host, then reinstall so the lockfile is regenerated."
    } >&2
    exit 2
  fi
fi
exit 0

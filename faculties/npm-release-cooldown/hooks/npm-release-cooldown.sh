#!/usr/bin/env bash
# PreToolUse hook (Bash): makes sure npm's release-age window is in force before any install,
# and blocks attempts to override it. npm itself then refuses versions younger than the window.
#
# Tunable (environment): NPM_COOLDOWN_DAYS, default 7.
set -euo pipefail
shopt -s nocasematch

INPUT=$(cat)
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
CWD=$(jq -r '.cwd // empty' <<<"$INPUT")
[[ -n "$CWD" && -d "$CWD" ]] && cd "$CWD"
DAYS=${NPM_COOLDOWN_DAYS:-7}

[[ "$CMD" =~ npm ]] || exit 0

block() {
  {
    echo "BLOCKED by npm-release-cooldown: $1"
    echo "Versions must be at least $DAYS days old before they are installed (min-release-age=$DAYS in the project .npmrc). If a newer release is needed urgently, for example a security fix, ask the user; they can exempt one package with min-release-age-exclude."
  } >&2
  exit 2
}

RE_OVERRIDE='--min-release-age|--before([=[:space:]]|$)|npm_config_min_release_age|npm_config_before|min-release-age-exclude'
RE_INSTALL='npm[[:space:]]+(install|i|add|ci|update|up|upgrade|install-test|it|dedupe|audit[[:space:]]+fix)([[:space:]]|$)'

[[ "$CMD" =~ $RE_OVERRIDE ]] && block "the command overrides the release-age window."

if [[ "$CMD" =~ $RE_INSTALL ]]; then
  AGE=$(npm config get min-release-age 2>/dev/null || echo unknown)
  if [[ "$AGE" == "undefined" || "$AGE" == "unknown" ]]; then
    block "this npm version does not support min-release-age; upgrade npm."
  fi
  if ! [[ "$AGE" =~ ^[0-9]+$ ]] || ((AGE < DAYS)); then
    block "min-release-age is '$AGE' for this project. Add min-release-age=$DAYS to the project .npmrc first."
  fi
fi
exit 0

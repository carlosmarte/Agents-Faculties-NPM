#!/usr/bin/env bash
# PreToolUse hook (Bash): registry-facing npm commands (publishing, authentication, ownership,
# tags) are outward-facing and hard to undo, so they always need a human's confirmation.
set -euo pipefail

INPUT=$(cat)
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")

RE='(^|[;&|[:space:]])(npm|pnpm|yarn)[[:space:]]+(npm[[:space:]]+)?(publish|unpublish|login|adduser|logout|token|owner|access|deprecate|undeprecate|dist-tag|dist-tags|profile|team|org|hook)([[:space:]]|$)'
[[ "$CMD" =~ $RE ]] || exit 0
ACTION=${BASH_REMATCH[4]}

# A dry run publishes nothing.
RE_DRY='--dry-run([[:space:]]|=true|$)'
if [[ "$ACTION" == "publish" && "$CMD" =~ $RE_DRY ]]; then
  exit 0
fi

jq -n --arg a "$ACTION" '{hookSpecificOutput: {hookEventName: "PreToolUse",
  permissionDecision: "ask",
  permissionDecisionReason: ("npm-publish-guard: this command runs `npm " + $a + "`, which changes what is on the npm registry or how this machine is authenticated to it. Confirm that you want the agent to run it.")}}'
exit 0

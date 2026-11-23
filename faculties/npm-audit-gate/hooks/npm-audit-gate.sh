#!/usr/bin/env bash
set -euo pipefail

# Read the tool payload from stdin (JSON)
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only trigger on npm install / i / add commands
if [[ ! "$COMMAND" =~ npm[[:space:]]+(install|i|add)([[:space:]]|$) ]]; then
  exit 0
fi

# Run npm audit at the strictest level (change to moderate/high if needed)
if ! AUDIT_OUT=$(npm audit --audit-level=low 2>&1); then
  {
    echo "BLOCKED: npm audit detected vulnerabilities after running: $COMMAND"
    echo ""
    echo "$AUDIT_OUT"
    echo ""
    echo "Action required: Run 'npm audit fix', upgrade to a patched version, or uninstall the vulnerable package and choose a secure alternative. Do not proceed until 'npm audit --audit-level=low' exits with 0."
  } >&2
  exit 2
fi

exit 0

#!/usr/bin/env bash
# PreToolUse hook (Read, Edit, Write, Grep, Bash):
#   - denies direct access to credential files (.env, ~/.npmrc, private keys, cloud credentials)
#   - asks the user before a shell command that names such a file
#   - denies shell commands that print secret-looking environment variables
#   - scans what a `git commit` would record and denies the commit if it contains a secret
set -euo pipefail

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT")
CWD=$(jq -r '.cwd // empty' <<<"$INPUT")
[[ -n "$CWD" && -d "$CWD" ]] && cd "$CWD"

deny() {
  echo "BLOCKED by secrets-guard: $1" >&2
  exit 2
}

ask() {
  jq -n --arg r "secrets-guard: $1" '{hookSpecificOutput: {hookEventName: "PreToolUse",
    permissionDecision: "ask", permissionDecisionReason: $r}}'
  exit 0
}

sensitive() {
  local path=$1 base
  path=${path/#\~/$HOME}
  path=${path/#\$HOME/$HOME}
  path=${path/#\$\{HOME\}/$HOME}
  base=$(basename -- "$path")
  case "$base" in
    .env.example | .env.sample | .env.template | .env.dist | .env.defaults) return 1 ;;
    .env | .env.* | .netrc | .pypirc | .git-credentials | id_rsa | id_dsa | id_ecdsa | id_ed25519 | \
      *.pem | *.key | *.p12 | *.pfx | *.keystore | *.jks) return 0 ;;
  esac
  case "$path" in
    "$HOME/.npmrc" | */.aws/credentials | */.docker/config.json | */.kube/config | */.config/gcloud/*) return 0 ;;
    */.ssh/*.pub | */.ssh/known_hosts | */.ssh/config) return 1 ;;
    */.ssh/*) return 0 ;;
  esac
  return 1
}

# Prints the files in a unified diff (stdin) whose added lines contain a secret.
SECRET_RE='npm_[A-Za-z0-9]{36}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-ant-[A-Za-z0-9_-]{20,}|sk_live_[A-Za-z0-9]{16,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|_authToken[[:space:]]*=[[:space:]]*[^$[:space:]]'
files_with_secrets() {
  awk '/^\+\+\+ /{f=substr($0,7); next} /^\+/{print f "\t" substr($0,2)}' |
    grep -E -- "$SECRET_RE" | cut -f1 | sort -u || true
}

case "$TOOL" in
  Read | Edit | Write | Grep)
    FILE=$(jq -r '.tool_input.file_path // .tool_input.path // empty' <<<"$INPUT")
    if [[ -n "$FILE" ]] && sensitive "$FILE"; then
      deny "$FILE is a credential file. Do not read or modify it; reference secrets through environment variables, and ask the user to make any change to this file themselves."
    fi
    exit 0
    ;;
  Bash) ;;
  *) exit 0 ;;
esac

CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")

RE_PRINT_VAR='(echo|printf|printenv)[^;&|]*(TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|PRIVATE_KEY|CREDENTIAL)'
RE_DUMP_ENV='(^|[;&|])[[:space:]]*(printenv|env|export[[:space:]]+-p|set)[[:space:]]*($|[|>;&])'
[[ "$CMD" =~ $RE_PRINT_VAR ]] && deny "the command prints a secret-looking environment variable. Use the variable without displaying it."
[[ "$CMD" =~ $RE_DUMP_ENV ]] && deny "the command dumps the whole environment, which includes secrets. Query the specific non-secret variable you need."

RE_COMMIT='git[[:space:]]+([^;&|]*[[:space:]])?commit([[:space:]]|$)'
if [[ "$CMD" =~ $RE_COMMIT ]] && git rev-parse --git-dir >/dev/null 2>&1; then
  HITS=$(git diff --cached -U0 --no-color 2>/dev/null | files_with_secrets)
  RE_STAGES_MORE='git[[:space:]]+([^;&|]*[[:space:]])?(add|commit[^;&|]*[[:space:]]-[a-zA-Z]*a)'
  if [[ "$CMD" =~ $RE_STAGES_MORE ]]; then
    # The command stages files itself, so also scan unstaged changes and untracked files.
    MORE=$(git diff -U0 --no-color 2>/dev/null | files_with_secrets)
    UNTRACKED=$(git ls-files --others --exclude-standard -z 2>/dev/null |
      xargs -0 grep -IlE -- "$SECRET_RE" 2>/dev/null || true)
    HITS=$(printf '%s\n%s\n%s\n' "$HITS" "$MORE" "$UNTRACKED" | grep -v '^$' | sort -u || true)
  fi
  if [[ -z "$HITS" ]] && command -v gitleaks >/dev/null 2>&1; then
    if ! gitleaks protect --staged --redact --no-banner >/dev/null 2>&1; then
      HITS="(reported by gitleaks; run 'gitleaks protect --staged --redact' for details)"
    fi
  fi
  if [[ -n "$HITS" ]]; then
    deny "this commit would record a secret. Files:
$HITS
Remove the secret, load it from an environment variable instead, and tell the user so the credential can be rotated if it was ever real."
  fi
fi

set -f
for token in $(grep -oE "[^[:space:]'\"=<>|;&()]+" <<<"$CMD" || true); do
  if sensitive "$token"; then
    ask "this command names the credential file '$token'. Approve only if it does not expose the contents to the agent."
  fi
done
exit 0

#!/usr/bin/env bash
# Static checks for GitHub Actions workflows.
#   actions-check.sh [<repo-dir>]
# Fails (exit 1) on: actions not pinned to a commit SHA, missing or write-all permissions,
# pull_request_target workflows that check out the pull request's code, and untrusted event
# text interpolated directly into a step. The last check is a line-based heuristic.
set -euo pipefail

cd "${1:-.}"
DIR=.github/workflows
FILES=$(find "$DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | sort || true)
if [[ -z "$FILES" ]]; then
  echo "ok   no workflows in $DIR"
  exit 0
fi

FAILED=0
fail() {
  echo "FAIL $1"
  FAILED=1
}

UNTRUSTED='\$\{\{[^}]*(github\.event\.(issue|pull_request|comment|review|review_comment|discussion|head_commit|commits|pages|workflow_run)[^}]*\.(title|body|message|name|email|label|ref|head_ref|default_branch)|github\.head_ref)[^}]*\}\}'
# Safe places for untrusted text: an `if:` condition or an UPPER_CASE env assignment.
SAFE_KEY='^[[:space:]]*(-[[:space:]]*)?(if|[A-Z_][A-Z0-9_]*):'

while IFS= read -r file; do
  # 1. Every third-party action pinned to a full commit SHA.
  while IFS= read -r hit; do
    line=${hit%%:*}
    ref=$(sed -E 's/^[0-9]+:[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*//; s/[[:space:]]*#.*$//; s/^["'\'']//; s/["'\'']$//' <<<"$hit")
    case "$ref" in
      ./* | ../*) continue ;;
      docker://*) [[ "$ref" == *@sha256:* ]] || fail "$file:$line: container image not pinned to a digest: $ref" ;;
      *) [[ "$ref" =~ @[0-9a-f]{40}$ ]] || fail "$file:$line: action not pinned to a commit SHA: $ref" ;;
    esac
  done < <(grep -nE '^[[:space:]]*(-[[:space:]]*)?uses:' "$file" || true)

  # 2. Explicit, least-privilege token permissions.
  if ! grep -qE '^[[:space:]]*permissions:' "$file"; then
    fail "$file: no 'permissions:' block, so the token gets the repository default (often write)."
  fi
  while IFS= read -r hit; do
    fail "$file:${hit%%:*}: 'permissions: write-all' grants every scope."
  done < <(grep -nE '^[[:space:]]*permissions:[[:space:]]*write-all' "$file" || true)

  # 3. pull_request_target must never run the pull request's own code.
  if grep -qE 'pull_request_target' "$file"; then
    if grep -qE 'github\.event\.pull_request\.head\.(sha|ref)|refs/pull/' "$file"; then
      fail "$file: pull_request_target workflow checks out pull request code, giving untrusted code access to secrets."
    else
      echo "warn $file: uses pull_request_target (runs with secrets on external pull requests); keep it free of PR-controlled code."
    fi
  fi

  # 4. Untrusted event text must not be interpolated into scripts.
  while IFS= read -r hit; do
    text=${hit#*:}
    [[ "$text" =~ $SAFE_KEY ]] && continue
    fail "$file:${hit%%:*}: untrusted event data interpolated directly; pass it through 'env:' and use the shell variable."
  done < <(grep -nE "$UNTRUSTED" "$file" || true)
done <<<"$FILES"

((FAILED)) && exit 1
echo "ok   $(wc -l <<<"$FILES" | tr -d ' ') workflow file(s) passed"

#!/usr/bin/env bash
# Verifies package-lock.json: present, committed, and every dependency comes from an expected
# HTTPS registry with an integrity hash.
#   lockfile-check.sh [--dir <project>]
# Allowed hosts: every registry named in the project .npmrc (registry.npmjs.org if none),
# plus any in LOCKFILE_ALLOWED_HOSTS (comma-separated).
set -euo pipefail

if [[ "${1:-}" == "--dir" ]]; then cd "${2:?--dir needs a path}"; fi
LOCK=package-lock.json
[[ -f npm-shrinkwrap.json ]] && LOCK=npm-shrinkwrap.json

FAILED=0
fail() {
  echo "FAIL $1"
  FAILED=1
}

if [[ ! -f "$LOCK" ]]; then
  echo "FAIL no package-lock.json. Run 'npm install --package-lock-only' and commit it."
  exit 1
fi

if git rev-parse --git-dir >/dev/null 2>&1 && git check-ignore -q "$LOCK"; then
  fail "$LOCK is gitignored. The lockfile must be committed."
fi

VERSION=$(jq -r '.lockfileVersion // 1' "$LOCK")
if ((VERSION < 2)); then
  echo "FAIL lockfileVersion $VERSION is too old to verify. Regenerate with a current npm."
  exit 1
fi

HOSTS=$(sed -nE 's#^[[:space:]]*(@[^:]+:)?registry[[:space:]]*=[[:space:]]*["'\'']?[a-z]+://([^/"'\'']+).*#\2#p' .npmrc 2>/dev/null || true)
[[ -z "$HOSTS" ]] && HOSTS=registry.npmjs.org
HOSTS=$(printf '%s\n%s\n' "$HOSTS" "$(tr ',' '\n' <<<"${LOCKFILE_ALLOWED_HOSTS:-}")" | grep -v '^$' | sort -u)

FINDINGS=$(jq -r --arg hosts "$HOSTS" '
  ($hosts | split("\n")) as $allowed
  | .packages // {} | to_entries[]
  | select(.key | test("(^|/)node_modules/"))
  | select((.value.link // false) or (.value.inBundle // false) | not)
  | .key as $k | (.value.resolved // "") as $r
  | if $r == "" then "\($k): no resolved URL"
    elif ($r | test("^https://") | not) then "\($k): not an HTTPS registry tarball: \($r)"
    elif ($allowed | index($r | capture("^https://(?<h>[^/]+)").h)) == null then "\($k): unexpected host: \($r)"
    elif (.value.integrity // "") == "" then "\($k): no integrity hash"
    else empty end' "$LOCK")

if [[ -n "$FINDINGS" ]]; then
  while IFS= read -r line; do fail "$line"; done <<<"$FINDINGS"
  echo "     allowed hosts: $(tr '\n' ' ' <<<"$HOSTS")"
fi

((FAILED)) && exit 1
echo "ok   $LOCK: $(jq '[.packages // {} | keys[] | select(. != "")] | length' "$LOCK") packages, all from allowed HTTPS registries with integrity hashes"

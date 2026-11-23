#!/usr/bin/env bash
# Verifies that the project .npmrc pins its registries and that the lockfile obeys the pins.
#   registry-check.sh [--dir <project>] [--require @scope ...]
# --require @scope fails unless that scope is pinned to a registry in .npmrc.
set -euo pipefail

REQUIRED=()
while (($#)); do
  case "$1" in
    --dir)
      cd "${2:?--dir needs a path}"
      shift 2
      ;;
    --require)
      REQUIRED+=("${2:?--require needs a scope}")
      shift 2
      ;;
    *)
      echo "usage: registry-check.sh [--dir <project>] [--require @scope ...]" >&2
      exit 2
      ;;
  esac
done

FAILED=0
fail() {
  echo "FAIL $1"
  FAILED=1
}

if [[ ! -f .npmrc ]]; then
  echo "FAIL no project .npmrc. Add an explicit 'registry=' line."
  exit 1
fi

# "name<TAB>url" for the default registry (name "default") and each scoped registry.
PINS=$(sed -nE \
  -e 's#^[[:space:]]*registry[[:space:]]*=[[:space:]]*["'\'']?([^"'\''[:space:]]+).*#default\t\1#p' \
  -e 's#^[[:space:]]*(@[^:[:space:]]+):registry[[:space:]]*=[[:space:]]*["'\'']?([^"'\''[:space:]]+).*#\1\t\2#p' .npmrc)

grep -q "^default$(printf '\t')" <<<"$PINS" ||
  fail ".npmrc has no explicit 'registry=' line, so the default can be changed by user or global config."

while IFS=$'\t' read -r name url; do
  [[ -z "$name" ]] && continue
  if [[ "$url" != https://* ]]; then
    fail "$name registry is not HTTPS: $url"
  else
    echo "ok   $name -> $url"
  fi
done <<<"$PINS"

for scope in ${REQUIRED[@]+"${REQUIRED[@]}"}; do
  grep -q "^$scope$(printf '\t')" <<<"$PINS" || fail "$scope is not pinned. Add '$scope:registry=https://...' to .npmrc."
done

# Packages in a pinned scope must have been resolved from that scope's registry.
if [[ -f package-lock.json ]]; then
  while IFS=$'\t' read -r name url; do
    [[ "$name" == @* && "$url" == https://* ]] || continue
    host=$(sed -E 's#^https://([^/]+).*#\1#' <<<"$url")
    STRAY=$(jq -r --arg scope "$name" --arg host "$host" '
      .packages // {} | to_entries[]
      | select(.key | test("(^|/)node_modules/" + $scope + "/[^/]+$"))
      | select((.value.link // false) | not)
      | (.value.resolved // "") as $r
      | select($r != "" and ($r | startswith("https://" + $host + "/") | not))
      | "\(.key) resolved from \($r)"' package-lock.json)
    if [[ -n "$STRAY" ]]; then
      while IFS= read -r line; do fail "$line (expected $host)"; done <<<"$STRAY"
    fi
  done <<<"$PINS"
fi

((FAILED)) && exit 1
echo "ok   registries pinned"

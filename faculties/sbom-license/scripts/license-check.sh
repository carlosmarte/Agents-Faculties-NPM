#!/usr/bin/env bash
# Checks the licence of every locked dependency against an allowlist.
#   license-check.sh [--dir <project>] [--prod]
# --prod ignores devDependencies. Allowlist: .license-allowlist in the project root (one SPDX
# identifier per line); a permissive default set is used if the file does not exist.
set -euo pipefail

PROD=false
while (($#)); do
  case "$1" in
    --dir)
      cd "${2:?--dir needs a path}"
      shift 2
      ;;
    --prod)
      PROD=true
      shift
      ;;
    *)
      echo "usage: license-check.sh [--dir <project>] [--prod]" >&2
      exit 2
      ;;
  esac
done

LOCK=package-lock.json
if [[ ! -f "$LOCK" ]]; then
  echo "FAIL no $LOCK to read licences from"
  exit 1
fi

DEFAULT_ALLOWED='MIT
MIT-0
ISC
Apache-2.0
BSD-2-Clause
BSD-3-Clause
0BSD
BlueOak-1.0.0
CC0-1.0
CC-BY-4.0
Unlicense
Python-2.0'

if [[ -f .license-allowlist ]]; then
  ALLOWED=$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' .license-allowlist | grep -v '^$' || true)
else
  ALLOWED=$DEFAULT_ALLOWED
fi

# An SPDX expression passes if any OR-alternative has all of its AND-terms allowed.
FINDINGS=$(jq -r --arg allowed "$ALLOWED" --argjson prod "$PROD" '
  ($allowed | split("\n")) as $ok
  | .packages // {} | to_entries[]
  | select(.key != "" and ((.value.link // false) | not))
  | select(($prod | not) or ((.value.dev // false) | not))
  | (.value.license // "UNKNOWN" | tostring) as $lic
  | select(
      ($lic | gsub("[()]"; "") | split(" OR ")
        | any(split(" AND ") | all((sub(" WITH .*$"; "")) as $id | $ok | index($id) != null)))
      | not)
  | "\(.key | sub("^.*node_modules/"; ""))@\(.value.version // "?"): \($lic)"' "$LOCK" | sort -u)

if [[ -n "$FINDINGS" ]]; then
  echo "FAIL licences not on the allowlist:"
  sed 's/^/  /' <<<"$FINDINGS"
  exit 1
fi
echo "ok   all dependency licences are on the allowlist"

#!/usr/bin/env bash
# PreToolUse hook (Bash): vets every package named in an install command before it is
# downloaded. Blocks names that do not exist (typos, hallucinations), very new packages,
# rarely downloaded packages, packages with no source repository, and remote URL / git specs.
#
# Tunables (environment):
#   NPM_VET_MIN_AGE_DAYS          default 30
#   NPM_VET_MIN_WEEKLY_DOWNLOADS  default 1000
# Overrides: .npm-vetting-allowlist in the project root (one package name per line).
set -euo pipefail
set -f # no globbing while word-splitting package specs

INPUT=$(cat)
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
CWD=$(jq -r '.cwd // empty' <<<"$INPUT")
[[ -n "$CWD" && -d "$CWD" ]] && cd "$CWD"

MIN_AGE=${NPM_VET_MIN_AGE_DAYS:-30}
MIN_DL=${NPM_VET_MIN_WEEKLY_DOWNLOADS:-1000}
ALLOWLIST=.npm-vetting-allowlist
PUBLIC_REGISTRY_HOST=registry.npmjs.org

SEGMENTS=$(grep -oE '(npm[[:space:]]+(install|i|add)|pnpm[[:space:]]+(install|i|add)|yarn[[:space:]]+add)([[:space:]]+[^;&|]*)?' <<<"$CMD" || true)
[[ -z "$SEGMENTS" ]] && exit 0

PROBLEMS=()
NOW=$(date +%s)

allowlisted() {
  [[ -f "$ALLOWLIST" ]] && sed -e 's/#.*//' -e 's/[[:space:]]//g' "$ALLOWLIST" | grep -Fxq "$1"
}

registry_host_for() {
  local name=$1 reg=""
  if [[ "$name" == @*/* ]]; then
    reg=$(npm config get "${name%%/*}:registry" 2>/dev/null || true)
  fi
  if [[ -z "$reg" || "$reg" == "undefined" ]]; then
    reg=$(npm config get registry 2>/dev/null || true)
  fi
  sed -E 's#^[a-z]+://([^/]+).*#\1#' <<<"$reg"
}

vet() {
  local name=$1 info created age downloads repo
  if ! info=$(npm view "$name" name time.created repository.url --json 2>&1); then
    if grep -q 'E404' <<<"$info"; then
      PROBLEMS+=("$name: does not exist on the registry. Likely a typo or an invented name; do not guess a replacement, find the real package.")
    else
      PROBLEMS+=("$name: could not be vetted because the registry lookup failed (not a verdict on the package). Retry, or ask the user.")
    fi
    return
  fi

  created=$(jq -r '.["time.created"] // empty' <<<"$info" 2>/dev/null || true)
  if [[ -n "$created" ]]; then
    age=$(jq -rn --arg t "$created" --argjson now "$NOW" \
      '(($now - ($t | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)) / 86400) | floor')
    if ((age < MIN_AGE)); then
      PROBLEMS+=("$name: first published $age days ago (minimum $MIN_AGE).")
    fi
  else
    PROBLEMS+=("$name: the registry reports no creation date.")
  fi

  repo=$(jq -r '.["repository.url"] // empty' <<<"$info" 2>/dev/null || true)
  [[ -z "$repo" ]] && PROBLEMS+=("$name: declares no source repository.")

  # Download counts exist only for the public registry; never send private names there.
  if [[ "$(registry_host_for "$name")" == "$PUBLIC_REGISTRY_HOST" ]]; then
    downloads=$(curl -fsS --max-time 10 "https://api.npmjs.org/downloads/point/last-week/$name" 2>/dev/null |
      jq -r '.downloads // empty' 2>/dev/null || true)
    if [[ -n "$downloads" ]] && ((downloads < MIN_DL)); then
      PROBLEMS+=("$name: $downloads downloads last week (minimum $MIN_DL).")
    fi
  fi
}

while IFS= read -r segment; do
  # Drop the launcher and subcommand, e.g. "npm install".
  args=$(sed -E 's/^[a-z]+[[:space:]]+[a-z]+[[:space:]]*//' <<<"$segment")
  skip_next=0
  for word in $args; do
    word=${word//\"/}
    word=${word//\'/}
    if ((skip_next)); then
      skip_next=0
      continue
    fi
    case "$word" in
      --prefix | -C | -w | --workspace | --registry | --tag | --cache | --userconfig | --omit | --include | --before | --min-release-age | --loglevel)
        skip_next=1
        continue
        ;;
      -* | "" | '>'* | '<'* | [0-9]'>'*) continue ;;
      . | ./* | ../* | /* | '~'/* | file:* | *.tgz | *.tar.gz) continue ;; # local sources
    esac
    [[ "$word" == *@npm:* ]] && word=${word#*@npm:} # alias@npm:real-name
    case "$word" in
      http://* | https://* | git+* | git://* | ssh://* | github:* | gitlab:* | bitbucket:* | gist:* | *.git | *.git#*)
        PROBLEMS+=("$word: remote URL / git source bypasses the registry and cannot be vetted.")
        continue
        ;;
    esac
    if [[ "$word" == @* ]]; then
      rest=${word#@}
      name="@${rest%%@*}"
    else
      name=${word%%@*}
    fi
    if ! [[ "$name" =~ ^(@[a-z0-9~-][a-z0-9._~-]*/)?[a-z0-9~-][a-z0-9._~-]*$ ]]; then
      PROBLEMS+=("$word: not a registry package name (GitHub shorthand and other non-registry sources cannot be vetted).")
      continue
    fi
    allowlisted "$name" && continue
    vet "$name"
  done
done <<<"$SEGMENTS"

if ((${#PROBLEMS[@]})); then
  {
    echo "BLOCKED by npm-package-vetting: nothing was installed."
    printf '  - %s\n' "${PROBLEMS[@]}"
    echo "Choose an established, maintained package instead. If one of these is genuinely wanted, ask the user to add its name to $ALLOWLIST; do not add it yourself."
  } >&2
  exit 2
fi
exit 0

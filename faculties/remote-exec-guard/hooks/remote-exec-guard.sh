#!/usr/bin/env bash
# PreToolUse hook (Bash): blocks running code straight off the network.
#   - curl/wget piped or substituted into a shell or interpreter
#   - npx / npm exec / pnpm dlx / yarn dlx / bunx of a package that is not already a
#     dependency of this project
# Override for trusted tools: .npx-allowlist in the project root (one package name per line).
set -euo pipefail
set -f

INPUT=$(cat)
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
CWD=$(jq -r '.cwd // empty' <<<"$INPUT")
[[ -n "$CWD" && -d "$CWD" ]] && cd "$CWD"
ALLOWLIST=.npx-allowlist

block() {
  echo "BLOCKED by remote-exec-guard: $1" >&2
  exit 2
}

RE_PIPE='(curl|wget)[^;&]*\|[[:space:]]*(sudo[[:space:]]+)?(env[[:space:]]+)?(bash|sh|zsh|dash|ksh|fish|python[0-9.]*|node|perl|ruby|php)([[:space:]]|$)'
RE_SUBST='(bash|sh|zsh|source|eval|python[0-9.]*|node)[^;&|]*(<\(|\$\()[[:space:]]*(curl|wget)'
if [[ "$CMD" =~ $RE_PIPE || "$CMD" =~ $RE_SUBST ]]; then
  block "the command downloads a script and executes it unseen. Download it to a file, read it, then run it; or ask the user to run the installer."
fi

SEGMENTS=$(grep -oE '(^|[;&|[:space:]])(npx|pnpx|bunx|npm[[:space:]]+(exec|x)|pnpm[[:space:]]+dlx|yarn[[:space:]]+dlx)[[:space:]]+[^;&|]*' <<<"$CMD" || true)
[[ -z "$SEGMENTS" ]] && exit 0

allowed() {
  local name=$1
  [[ -d "node_modules/$name" || -e "node_modules/.bin/$name" ]] && return 0
  [[ -f "$ALLOWLIST" ]] && sed -e 's/#.*//' -e 's/[[:space:]]//g' "$ALLOWLIST" | grep -Fxq "$name"
}

while IFS= read -r segment; do
  args=$(sed -E 's/^[;&|[:space:]]*(npm[[:space:]]+(exec|x)|pnpm[[:space:]]+dlx|yarn[[:space:]]+dlx|npx|pnpx|bunx)[[:space:]]+//' <<<"$segment")
  PKGS=()
  local_only=0
  take_pkg=0
  skip_next=0
  for word in $args; do
    word=${word//\"/}
    word=${word//\'/}
    if ((take_pkg)); then
      PKGS+=("$word")
      take_pkg=0
      continue
    fi
    if ((skip_next)); then
      skip_next=0
      continue
    fi
    case "$word" in
      --no | --no-install) local_only=1 ;; # refuses to download; runs only what is installed
      -p | --package) take_pkg=1 ;;
      --package=*) PKGS+=("${word#--package=}") ;;
      -c | --call | -w | --workspace | --prefix | --registry) skip_next=1 ;;
      --) ;;
      -*) ;;
      *)
        ((${#PKGS[@]})) || PKGS+=("$word")
        break
        ;;
    esac
  done
  ((local_only)) && continue

  for spec in ${PKGS[@]+"${PKGS[@]}"}; do
    case "$spec" in
      http://* | https://* | git+* | git://* | github:* | gitlab:* | bitbucket:* | *.git)
        block "'$spec' is fetched from a URL / git source and executed immediately."
        ;;
      . | ./* | ../* | /*) continue ;;
    esac
    if [[ "$spec" == @* ]]; then
      rest=${spec#@}
      name="@${rest%%@*}"
    else
      name=${spec%%@*}
    fi
    allowed "$name" || block "'$name' is not a dependency of this project, so this would download it from the registry and execute it immediately. Add it as a devDependency first (so it is vetted, locked and audited), or ask the user to add it to $ALLOWLIST."
  done
done <<<"$SEGMENTS"
exit 0

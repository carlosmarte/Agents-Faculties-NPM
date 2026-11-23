# Faculties

Security guardrails for AI coding agents working in npm projects. Each folder is one
faculty and is self-contained. A faculty can include any of:

- `SKILL.md` — a procedure the agent loads when the task calls for it
- `RULE.md` — a standing instruction the agent always follows
- `hooks/` — a script the harness runs on every tool call, which the agent cannot skip
- `scripts/` — checkers the skill, the hook or CI can run

| Faculty | Skill | Rule | Hook | Purpose |
|---|:-:|:-:|:-:|---|
| `npmrc-devsecops` | ✓ | | | Keep `audit=true` and `audit-level=low` in the project `.npmrc` |
| `npm-audit-gate` | | ✓ | post | Run `npm audit` after every install; zero vulnerabilities to proceed |
| `npm-bypass-guard` | | | pre | Block `--no-audit`, `--force`, audit env vars, and `.npmrc` edits that weaken audits |
| `npm-install-scripts-guard` | ✓ | | pre | Dependency install scripts run only for packages a human approved |
| `npm-package-vetting` | | | pre | Before install, reject non-existent, brand-new, obscure or non-registry packages |
| `npm-release-cooldown` | ✓ | | pre | Refuse versions published in the last 7 days (`min-release-age`) |
| `secrets-guard` | | ✓ | pre | Keep credential files out of the agent's reach and secrets out of commits |
| `npm-publish-guard` | | | pre | Ask a human before `npm publish`, `login`, `token`, `owner` and similar |
| `lockfile-integrity` | ✓ | | pre + post | Lockfile is committed, npm-generated, HTTPS-only, with integrity hashes |
| `registry-pinning` | ✓ | | | Pin default and scoped registries to prevent dependency confusion |
| `remote-exec-guard` | | | pre | Block `curl \| bash` and `npx` of packages that are not project dependencies |
| `gh-actions-hardening` | ✓ | ✓ | | SHA-pinned actions, least-privilege permissions, no untrusted interpolation |
| `vuln-triage` | ✓ | | | What to do when `npm audit fix` cannot resolve a finding |
| `sbom-license` | ✓ | | | Generate an SBOM and check dependency licences against an allowlist |

## Installing the hooks

Hooks follow the Claude Code hook contract: the tool call arrives as JSON on stdin, exit
code 2 blocks it and returns stderr to the agent, and a `permissionDecision: "ask"` reply
puts the decision in front of the user. They need `bash`, `jq` and `npm`.

`settings.example.json` in this folder registers every hook; merge it into the project's
`.claude/settings.json`. Each faculty also has its own `hooks/settings.example.json` if you
want only some of them. The paths assume this folder sits at `<project>/faculties`.

## Project `.npmrc` with every guardrail on

```ini
registry=https://registry.npmjs.org/
audit=true
audit-level=low
strict-allow-scripts=true
min-release-age=7
allow-git=none
allow-remote=none
```

The last four settings need a recent npm. Check with `npm config get <name>`: `undefined`
means the installed npm does not know the setting.

## Human-maintained override files

These live in the project root. The agent is told not to edit them on its own judgment.

| File | Used by | Meaning |
|---|---|---|
| `allowScripts` in `package.json` | `npm-install-scripts-guard` | Packages whose install scripts may run |
| `.npm-vetting-allowlist` | `npm-package-vetting` | Packages exempt from vetting, e.g. private ones |
| `.npx-allowlist` | `remote-exec-guard` | Tools that may be run with `npx` without being a dependency |
| `.license-allowlist` | `sbom-license` | Accepted SPDX licence identifiers |

## Limits

The hooks match commands by pattern. They stop an agent from taking the unsafe path by
accident or by default; they are not a sandbox, and a command that hides what it does (an
alias, a wrapper script, an encoded string) will get past them. Keep the same checks in CI.

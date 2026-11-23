---
name: npmrc-devsecops
description: Manage a project's .npmrc as a DevSecOps guardrail. Use when creating, editing, or reviewing an .npmrc, setting up a new npm project, before running npm install / npm ci in a repo, or when asked about npm audit settings, so that vulnerability audits cannot be silently disabled by a global or user-level npm config.
---

# .npmrc DevSecOps guardrail

## The rule

Every npm project's repo-level `.npmrc` (next to `package.json`) must contain:

```ini
audit=true
audit-level=low
```

**Why:** npm merges config from several places. A developer machine or CI image may have
`audit=false` in `~/.npmrc` or the global `npmrc`, which silently turns off vulnerability
reporting on `npm install`. The project `.npmrc` outranks both, so pinning the values there
means neither an agent nor a developer can accidentally rely on a config that disables audits.
`audit-level=low` makes `npm audit` exit non-zero for any known vulnerability, not only severe ones.

## Procedure

Run the bundled script from the project root (or pass `--dir <project>`). It needs only Node.

1. **Check** before installing dependencies or when reviewing a repo:

   ```sh
   node <skill-dir>/scripts/npmrc-guard.mjs check
   ```

   Exit code 0 means the guardrail is in place; 1 means it is missing or weakened.

2. **Fix** if the check fails:

   ```sh
   node <skill-dir>/scripts/npmrc-guard.mjs fix
   ```

   This creates `.npmrc` if needed, corrects wrong values in place, removes duplicate
   assignments of the two keys, and leaves every other line and comment untouched.

3. **Confirm** what npm actually resolves, from the project root:

   ```sh
   npm config get audit        # expect: true
   npm config get audit-level  # expect: low
   ```

4. Make sure `.npmrc` is committed, not gitignored.

## Rules for agents

- Never set `audit=false`, raise `audit-level`, or delete either line. If a user asks for
  that, explain the guardrail and get explicit confirmation first.
- Never pass `--no-audit` or `--audit=false` to npm commands, and never set
  `npm_config_audit` / `npm_config_audit_level` in the environment. Command-line flags and
  environment variables outrank the project `.npmrc`, so the file cannot defend against
  them. The script warns when such variables are set.
- When editing `.npmrc` for any other reason (registries, scopes, proxies), keep the two
  guardrail lines and re-run `check` afterwards.
- Never write a literal credential into a committed `.npmrc`. Reference an environment
  variable instead: `//registry.npmjs.org/:_authToken=${NPM_TOKEN}`. The script warns on
  literal `_authToken`, `_auth`, and `_password` values.
- A failing `npm audit` is a finding to report and fix (upgrade, override, or replace the
  dependency), not something to silence by loosening the config.

## Config precedence (highest first)

1. Command-line flags (`--no-audit`)
2. Environment variables (`npm_config_audit=false`)
3. Project `.npmrc` — where the guardrail lives
4. User `~/.npmrc`
5. Global `$PREFIX/etc/npmrc`
6. npm built-in defaults

## CI

Add the check as an early pipeline step so a weakened `.npmrc` fails the build:

```sh
node <skill-dir>/scripts/npmrc-guard.mjs check && npm ci && npm audit
```

---
name: npm-release-cooldown
description: Enforce a waiting period before newly published npm versions can be installed, using npm's min-release-age setting. Use when setting up an npm project, before installing or updating dependencies, when an install fails because no version is old enough, or when asked about release cooldowns or quarantining new package versions.
---

# npm release cooldown

## The rule

The project `.npmrc` must contain a release-age window of at least 7 days:

```ini
min-release-age=7
```

**Why:** compromised package versions are usually detected and unpublished within hours or
days. Refusing anything younger than the window means a hijacked release has normally been
pulled before it can reach this project. npm enforces the window itself while resolving the
dependency tree, including for transitive dependencies.

## Procedure

1. Confirm npm supports the setting. From the project root:

   ```sh
   npm config get min-release-age
   ```

   `undefined` means npm is too old; upgrade it. `null` means it is supported but unset.

2. Add `min-release-age=7` to the project `.npmrc` and commit it.

3. Install as normal. If npm errors because no version of a package is old enough, pin an
   older version that satisfies the range, or wait. Do not shorten the window.

## Exceptions

A security fix published inside the window is the one legitimate reason to go faster, and
`npm audit fix` will report when the window blocked a patched version. Tell the user which
package and advisory is involved and ask them to exempt that one package:

```ini
min-release-age-exclude[]=some-package
```

Remove the exemption once the release is older than the window.

## Rules for agents

- Never pass `--min-release-age`, `--before` or `--min-release-age-exclude`, and never set
  `npm_config_min_release_age` or `npm_config_before`. `before` takes precedence over
  `min-release-age`, so either one defeats the window.
- Never lower the value, remove the line, or add an exclusion without the user's approval.

## Hook

`hooks/npm-release-cooldown.sh` (PreToolUse on `Bash`) blocks the overrides above and blocks
installs unless `npm config get min-release-age` is at least `NPM_COOLDOWN_DAYS` (default 7).

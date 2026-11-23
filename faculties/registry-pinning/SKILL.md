---
name: registry-pinning
description: Pin npm registries in the project .npmrc to prevent dependency-confusion attacks on private packages. Use when a project uses private or internal npm packages, a private registry or mirror (Artifactory, Nexus, GitHub Packages, Verdaccio), when adding a scoped registry to .npmrc, or when asked about dependency confusion or substitution attacks.
---

# Registry pinning

## Why

In a dependency-confusion attack, someone publishes a package on the public registry using
the same name as one of your private packages, with a higher version. Any machine whose npm
is not told exactly where that name must come from may install the attacker's copy.

## Rules

- The project `.npmrc` states the default registry explicitly, over HTTPS, so user or global
  config cannot redirect it:

  ```ini
  registry=https://registry.npmjs.org/
  ```

- Every private package is **scoped** (`@acme/thing`, never a bare `acme-thing`), and every
  private scope is pinned to its registry:

  ```ini
  @acme:registry=https://npm.acme.example/
  //npm.acme.example/:_authToken=${ACME_NPM_TOKEN}
  ```

  npm then fetches `@acme/*` only from that registry. Unscoped private names cannot be pinned
  this way, which is why they are not allowed.

- Credentials are environment-variable references, never literal tokens.
- Keep the `audit=true` and `audit-level=low` lines from the `npmrc-devsecops` skill.

## Procedure

1. Ask the user which scopes are private and which registry serves each, if the repo does
   not already say. Do not guess registry URLs.

2. Add the lines above to the project `.npmrc`.

3. **Check** from the project root, naming each private scope:

   ```sh
   <skill-dir>/scripts/registry-check.sh --require @acme
   ```

   It fails if the default registry is not explicit, any registry is not HTTPS, a required
   scope is not pinned, or the lockfile shows a package from a pinned scope that was resolved
   from a different host.

4. If the lockfile check fails, treat it as a possible substitution: tell the user, delete
   `node_modules`, and reinstall with the pins in place. Do not just re-run until it passes.

5. Recommend to the user that the organisation also registers its scope on the public npm
   registry, so nobody else can claim it.

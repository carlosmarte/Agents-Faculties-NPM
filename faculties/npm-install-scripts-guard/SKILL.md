---
name: npm-install-scripts-guard
description: Stop npm dependency lifecycle scripts (preinstall, install, postinstall) from running unless a human has reviewed and approved the package, using npm's allowScripts policy in strict mode. Use when setting up an npm project, before npm install / npm ci, when an install fails with ESTRICTALLOWSCRIPTS, when a package fails because its install script did not run (native addons, esbuild, sharp, puppeteer), or when asked about ignore-scripts or allowScripts.
---

# npm install-scripts guard

## The rule

The project `.npmrc` must contain:

```ini
strict-allow-scripts=true
```

**Why:** a dependency's install script runs arbitrary code on the machine the moment it is
installed, before anyone has read it, and that includes transitive dependencies you never
chose. It is the main delivery route for npm supply-chain malware.

Current npm tracks approvals in the `allowScripts` field of `package.json`, but by default it
only *warns* about unreviewed scripts and still runs them. `strict-allow-scripts=true` turns
that warning into a failed install (`ESTRICTALLOWSCRIPTS`), so nothing unreviewed runs.

Check that npm supports it:

```sh
npm config get strict-allow-scripts   # false or true = supported; undefined = too old
```

On an npm that reports `undefined`, use `ignore-scripts=true` instead, which disables all
dependency scripts, and recommend upgrading npm.

## Procedure

1. Add `strict-allow-scripts=true` to the project `.npmrc` and commit it.

2. Install as normal. If it fails with `ESTRICTALLOWSCRIPTS`, nothing was installed, and
   npm can only approve or deny packages that are installed. So install once with scripts
   off, which is safe, then list what needs a decision:

   ```sh
   npm install --ignore-scripts      # add the package name when adding a new dependency
   npm install-scripts ls
   ```

3. For each package listed, decide with the user:

   - **Not needed** (most packages work without their install script): deny it. You may do
     this yourself; a denial only ever prevents code from running.

     ```sh
     npm install-scripts deny <pkg>
     ```

   - **Needed** (it downloads a binary or compiles a native addon, and fails at runtime
     without it): tell the user which package, what its script does, and why it is needed,
     and ask them to approve. Approvals are pinned to the installed version by default, so
     an upgrade needs a fresh review.

     ```sh
     npm install-scripts approve <pkg>
     ```

4. Run `npm rebuild` so approved scripts run, confirm a plain `npm install` now succeeds,
   and commit the `allowScripts` change in `package.json`.

5. After removing or upgrading dependencies, tidy stale entries: `npm install-scripts prune`.

## Rules for agents

- Never approve a package's scripts on your own judgment. That includes
  `npm install-scripts approve`, `npm approve-scripts`, and editing `allowScripts` by hand.
- Never use `--dangerously-allow-all-scripts`, `--allow-scripts`, `--no-strict-allow-scripts`
  or `--ignore-scripts=false`, the matching `npm_config_*` environment variables, or remove
  the `.npmrc` line.
- Never use `approve --all`. Each package is reviewed individually.

## Hook

`hooks/npm-install-scripts-guard.sh` (PreToolUse on `Bash|Write|Edit`) enforces this. It
blocks installs when the project has no enforced policy, blocks the bypasses above, and asks
the user to confirm any approval command or any edit to `allowScripts`.

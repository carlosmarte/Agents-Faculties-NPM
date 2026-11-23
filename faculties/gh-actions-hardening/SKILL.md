---
name: gh-actions-hardening
description: Harden GitHub Actions workflows against supply-chain and injection attacks by pinning actions to commit SHAs, setting least-privilege token permissions, and keeping untrusted input and pull-request code away from secrets. Use when creating, editing or reviewing any file in .github/workflows, adding a third-party action, or setting up CI or npm publishing from CI.
---

# GitHub Actions hardening

## Procedure

1. **Check** the repo's workflows:

   ```sh
   <skill-dir>/scripts/actions-check.sh [<repo-dir>]
   ```

   Exit code 1 lists each finding as `file:line`. Fix them using the rules below, then
   re-run until it passes. The untrusted-input check is a line-based heuristic, so also read
   the workflow yourself.

2. **Pin every third-party action to a full commit SHA**, keeping the version as a comment.
   Tags and branches can be moved to malicious code after you reviewed them; a SHA cannot.

   ```yaml
   - uses: actions/checkout@<40-character-sha> # v4.2.2
   ```

   Look the SHA up; never invent or reuse one from memory:

   ```sh
   gh api repos/actions/checkout/commits/v4.2.2 --jq .sha
   ```

3. **Declare token permissions.** Put `permissions: contents: read` at the top of the
   workflow, then grant extra scopes only on the job that needs them. Never `write-all`.

4. **Keep untrusted text out of scripts.** Issue titles, PR bodies, branch names and commit
   messages are attacker-controlled. Pass them through `env:` and use the shell variable:

   ```yaml
   - env:
       TITLE: ${{ github.event.pull_request.title }}
     run: echo "$TITLE"
   ```

   Writing `${{ github.event.pull_request.title }}` inside `run:` lets the author inject
   shell commands.

5. **Avoid `pull_request_target`.** It runs with secrets on pull requests from forks. If it
   is unavoidable, never check out or execute the pull request's code in that workflow.

6. **Scope secrets.** Give a secret only to the step that needs it, via `env:`. Never echo
   one. Prefer OIDC (`id-token: write`) over long-lived cloud or npm tokens.

7. **npm in CI.** Install with `npm ci`, then `npm audit --audit-level=low`. Publish only
   from a protected branch or tag, using trusted publishing or `npm publish --provenance`.

## Rules for agents

- Do not add an action from an author you cannot identify; prefer `actions/*`, `github/*`
  and the vendor's own organisation.
- Do not weaken `permissions`, unpin an action, or add `pull_request_target` to make a
  failing job pass.

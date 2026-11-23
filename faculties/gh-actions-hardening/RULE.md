---
description: Security requirements for GitHub Actions workflows
globs: [".github/workflows/*.yml", ".github/workflows/*.yaml"]
alwaysApply: false
---

# GitHub Actions Hardening

Whenever you create or change a workflow file:

1. **Pin actions:** Every third-party `uses:` references a full 40-character commit SHA with
   the version in a trailing comment. Look the SHA up with
   `gh api repos/<owner>/<repo>/commits/<tag> --jq .sha`; never write one from memory.
2. **Least privilege:** The workflow declares `permissions:` explicitly, defaulting to
   `contents: read`. Add write scopes per job, only where needed. **Never** `write-all`.
3. **No untrusted interpolation:** Never place `${{ github.event.* }}` text fields or
   `${{ github.head_ref }}` inside `run:` or script inputs. Pass them through `env:`.
4. **No `pull_request_target` with PR code:** Do not check out or run pull request code in a
   `pull_request_target` workflow.
5. **Secrets:** Expose a secret only to the step that uses it, and never print it.
6. **Verify before finishing:** Do not consider the task complete until
   `faculties/gh-actions-hardening/scripts/actions-check.sh` exits with code `0`.

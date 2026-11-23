---
description: Enforce zero-vulnerability npm installations using npm audit
globs: ["package.json", "package-lock.json"]
alwaysApply: true
---

# NPM Vulnerability Gate

Whenever you install, add, or update any package from the npm registry:

1. **Audit immediately:** Run `npm audit --audit-level=low` right after `npm install`.
2. **Resolve all findings:**
   - First, run `npm audit fix` to apply non-breaking patches.
   - If vulnerabilities remain, check if a newer major version resolves them without breaking the codebase.
   - **Never** use `--no-audit`, `--force` blindly, or ignore vulnerability reports.
3. **Reject unfixable packages:** If a newly added package has unresolved vulnerabilities with no patched release, immediately run `npm uninstall <package>` and select a maintained, vulnerability-free alternative.
4. **Verify before finishing:** Do not consider the task complete until `npm audit --audit-level=low` exits with code `0` (0 vulnerabilities).

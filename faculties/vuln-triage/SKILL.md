---
name: vuln-triage
description: Procedure for resolving npm audit findings that `npm audit fix` cannot fix on its own, covering transitive dependencies, overrides, replacing a package, and escalating a documented exception to a human. Use when npm audit still reports vulnerabilities after `npm audit fix`, when the npm-audit-gate blocks an install, or when asked to fix, assess or triage a vulnerable dependency or a CVE / GHSA advisory.
---

# Vulnerability triage

Work down this ladder and stop at the first step that gets
`npm audit --audit-level=low` to exit 0. Run the project's tests after every change.

## 1. Understand the finding

```sh
npm audit --json          # advisory id, severity, affected range, fixAvailable
npm explain <package>     # why it is installed: which direct dependency pulls it in
```

Note for each finding: the advisory (GHSA / CVE), whether the package is a direct or
transitive dependency, whether it is a production or dev dependency, and the first patched
version.

## 2. Non-breaking fix

```sh
npm audit fix
```

## 3. Upgrade the direct dependency

If the vulnerable package is transitive, upgrade the direct dependency that brings it in to
a release that depends on a patched version. If that needs a new major version, read its
changelog, make the code changes, and run the tests. Never use `npm audit fix --force`: it
applies major upgrades, and sometimes downgrades, without review.

## 4. Override the transitive version

If the parent has no release with the fix but a patched version of the vulnerable package
exists within a compatible range, force it in `package.json`:

```json
{
  "overrides": {
    "vulnerable-package": "^2.3.1"
  }
}
```

Then `npm install`, confirm with `npm explain vulnerable-package`, and run the tests.
Override to the smallest patched version, state in the commit message which advisory it
addresses, and remove the override once the parent catches up.

## 5. Replace the package

If no patched version exists, or the package is unmaintained, remove it
(`npm uninstall <package>`) and use a maintained alternative or the platform's built-in
functionality. For a newly added package this is the default answer, not a last resort.

## 6. Escalate; do not decide alone

If none of the above works, stop and report to the user:

- the advisory, the affected package and the dependency path;
- what you tried and why each step failed;
- whether the vulnerable code is reachable from this project, with your evidence, and
  whether it ships to production or is dev-only;
- the options: accept the risk temporarily, drop the feature, or fork and patch.

Accepting a risk is a human decision. If the user accepts it, record it in
`SECURITY-EXCEPTIONS.md`: advisory id, package and version, justification, the approver's
name, the date, and an expiry date no more than 30 days out.

`npm audit` has no way to ignore an individual advisory, so the audit gate stays red while
an exception is open. That is intended: it is the user's call to proceed past it, not yours.

## Never

- Use `--no-audit`, `--force`, or a raised `--audit-level` to make a finding disappear.
- Claim a finding is "not exploitable" without showing the reasoning.
- Leave an override or exception in place without a recorded reason.

---
name: sbom-license
description: Generate a software bill of materials (SBOM) for an npm project and check dependency licences against an allowlist. Use when asked for an SBOM, CycloneDX or SPDX output, a dependency inventory, licence compliance or a licence audit, when preparing a release, or after adding a dependency whose licence has not been checked.
---

# SBOM and licence check

## Generate an SBOM

From the project root, with dependencies installed (or add `--package-lock-only`):

```sh
npm sbom --sbom-format cyclonedx --omit dev > sbom.cdx.json   # CycloneDX
npm sbom --sbom-format spdx      --omit dev > sbom.spdx.json  # SPDX
```

- `--omit dev` describes what ships; leave it off for the full build-time inventory.
- Add `--sbom-type application` or `library` to match what the project is.
- An SBOM describes one build. Generate it in CI from the same lockfile as the release
  artefact and publish it alongside, rather than committing a copy that goes stale.

## Check licences

```sh
<skill-dir>/scripts/license-check.sh [--dir <project>] [--prod]
```

It reads each package's declared licence from `package-lock.json` and exits 1 listing every
package whose licence is not allowed. `--prod` skips devDependencies.

The allowlist is `.license-allowlist` in the project root, one SPDX identifier per line. If
the file does not exist, a permissive default set is used: MIT, MIT-0, ISC, Apache-2.0,
BSD-2-Clause, BSD-3-Clause, 0BSD, BlueOak-1.0.0, CC0-1.0, CC-BY-4.0, Unlicense, Python-2.0.

Expressions are handled: `(MIT OR GPL-3.0)` passes if either side is allowed, and
`MIT AND ISC` needs both.

## Handling findings

- **Copyleft or unlisted licence** (GPL, AGPL, LGPL, MPL, SSPL, proprietary): do not decide
  whether it is acceptable. Report the package, its licence, whether it is a production or
  dev dependency and what pulls it in (`npm explain <package>`), and propose an alternative.
- **`UNKNOWN`** or `SEE LICENSE IN ...`: read the package's LICENSE file and report what it
  says; do not assume.
- Only the user, or their legal owner, adds an identifier to `.license-allowlist`.

## Limits

The check trusts the licence each package declares in its own metadata. It does not read
licence texts or detect a package that declares one licence and ships another.

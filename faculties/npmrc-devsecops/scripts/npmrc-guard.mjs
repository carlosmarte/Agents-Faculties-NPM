#!/usr/bin/env node
// Checks or enforces the repo-level .npmrc audit guardrail.
//   node npmrc-guard.mjs check [--dir <project>]   exit 1 if the guardrail is missing or weakened
//   node npmrc-guard.mjs fix   [--dir <project>]   write the guardrail, preserving everything else
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const REQUIRED = { audit: 'true', 'audit-level': 'low' };

const [mode, ...rest] = process.argv.slice(2);
const dirFlag = rest.indexOf('--dir');
const dir = resolve(dirFlag >= 0 ? rest[dirFlag + 1] ?? '.' : '.');
const file = join(dir, '.npmrc');

if (mode !== 'check' && mode !== 'fix') {
  console.error('usage: npmrc-guard.mjs <check|fix> [--dir <project>]');
  process.exit(2);
}

const parse = (line) => {
  const m = /^\s*([^#;=\s][^=]*?)\s*=\s*(.*?)\s*$/.exec(line);
  return m ? { key: m[1], value: m[2].replace(/^(["'])(.*)\1$/, '$2') } : null;
};

const text = existsSync(file) ? readFileSync(file, 'utf8') : '';
const lines = text === '' ? [] : text.replace(/\n$/, '').split('\n');

// Last assignment wins in npm's ini parsing, so that is the effective value.
const effective = {};
for (const line of lines) {
  const kv = parse(line);
  if (kv && kv.key in REQUIRED) effective[kv.key] = kv.value;
}
const problems = Object.entries(REQUIRED)
  .filter(([key, want]) => effective[key] !== want)
  .map(([key, want]) => `${key}=${want} required, found ${effective[key] === undefined ? 'nothing' : `${key}=${effective[key]}`}`);

// Things a project .npmrc cannot defend against, or should not contain.
const warnings = [];
for (const [name, value] of Object.entries(process.env)) {
  if (/^npm_config_audit([_-]level)?$/i.test(name)) {
    warnings.push(`environment variable ${name}=${value} overrides the project .npmrc`);
  }
}
lines.forEach((line, i) => {
  const kv = parse(line);
  if (kv && /(_authToken|_auth|_password)$/.test(kv.key) && kv.value && !/^\$\{[^}]+\}$/.test(kv.value)) {
    warnings.push(`.npmrc line ${i + 1}: literal credential in ${kv.key}; use \${ENV_VAR} instead`);
  }
});

if (mode === 'fix' && problems.length) {
  const seen = new Set();
  const out = [];
  for (const line of lines) {
    const kv = parse(line);
    if (kv && kv.key in REQUIRED) {
      if (seen.has(kv.key)) continue; // drop duplicate assignments
      seen.add(kv.key);
      out.push(`${kv.key}=${REQUIRED[kv.key]}`);
    } else {
      out.push(line);
    }
  }
  for (const [key, want] of Object.entries(REQUIRED)) {
    if (!seen.has(key)) out.push(`${key}=${want}`);
  }
  writeFileSync(file, out.join('\n') + '\n');
  console.log(`fixed ${file}`);
  problems.forEach((p) => console.log(`  was: ${p}`));
} else if (problems.length) {
  console.error(`FAIL ${file}`);
  problems.forEach((p) => console.error(`  ${p}`));
} else {
  console.log(`ok ${file}`);
}

warnings.forEach((w) => console.error(`warning: ${w}`));
process.exit(mode === 'check' && problems.length ? 1 : 0);

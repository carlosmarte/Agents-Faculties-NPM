---
description: Keep credentials out of the agent's context, the terminal output, and the git history
alwaysApply: true
---

# Secrets Guard

1. **Do not open credential files.** Never read, search, print or edit `.env` files (other
   than `.env.example`-style templates), `~/.npmrc`, `.netrc`, private keys (`id_rsa`,
   `*.pem`, `*.key`), or cloud credential files (`~/.aws/credentials`, `~/.kube/config`,
   `~/.docker/config.json`). If a task needs a value from one, ask the user for the variable
   *name* and use it by reference.
2. **Do not display secrets.** Never `echo` or `printenv` a token, password or key, and never
   dump the whole environment (`env`, `printenv`, `set`).
3. **Reference, never embed.** In code and config, read secrets from environment variables.
   In `.npmrc`, write `//registry.npmjs.org/:_authToken=${NPM_TOKEN}`, never the literal token.
4. **Keep templates safe.** `.env.example` holds variable names and placeholder values only.
   Real `.env` files must be listed in `.gitignore`.
5. **Never commit a secret.** If a commit is blocked for containing one, remove it from the
   change; do not rewrite it to dodge the scanner (splitting, encoding, renaming).
6. **Report exposure.** If you come across a live credential in the repo, its history, logs
   or tool output, stop and tell the user so it can be rotated. Deleting the line does not
   make a leaked credential safe.

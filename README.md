# cowork-tooling

Session tooling for running Claude **Cowork** against GitHub from an ephemeral
sandbox: a single-token 1Password credential model, a per-session setup script,
and a safe front door for cloning/updating repos.

This repository is the **source of truth**. The live `bin/` used inside a Cowork
session is a read-only deployment of `main`; changes are made here on a branch,
pass the `gitleaks` check, and auto-merge to `main`.

## Layout

| Path | Purpose |
|------|---------|
| `bin/session-init.sh` | Run once per session. Wires the git credential helper, sets git identity + SSH commit signing (key from 1Password), clears stale per-repo identity overrides, sweeps stale `*.lock` files, and prints each repo's state. Derives the mount from its own location, so the changing per-session path is never passed in. |
| `bin/use-repo` | The single front door for repos: clones if absent, fast-forwards if present, checks out an optional branch. Never merges, never forces, never pushes, never touches uncommitted work. |
| `bin/repo-clone`, `bin/repo-latest` | Building blocks `use-repo` calls. Not invoked directly. |
| `bin/gh` | Token-injecting wrapper around the real `gh` (kept alongside as `gh-real`). |
| `bin/git-credential-op` | git credential helper that resolves the GitHub token from 1Password so plain `git` push/fetch/clone authenticate with no prefix. |
| `bin/op-run.sh` | Runs a command with secrets loaded from 1Password via `op run`. |

## Not in this repo (gitignored)

These live only in the local working folder and must be present for the tooling
to function. They are excluded from version control by design; see `.gitignore`.

- `.credentials/op_token` — the 1Password **service-account token**. The one
  at-rest secret; everything else is derived from it at runtime.
- `.op-env` — `op://` secret references (e.g. `GH_TOKEN=op://...`).
- `bin/gh-real`, `bin/op` — the upstream `gh` and `op` CLIs. Download from
  their official releases and place here.
- `repos/` — ephemeral checkouts.

## Bootstrap a fresh working folder

1. Clone this repo, or deploy `bin/` from it, into your Cowork working folder.
2. Add `.credentials/op_token` (mode 600) and `.op-env`.
3. Download the `gh` and `op` CLIs into `bin/` as `gh-real` and `op`.
4. Each session: approve the file-delete tool once, then
   `bash bin/session-init.sh`.

## Security model

- **No secret values are ever committed.** The scripts hold only *pointers*
  (1Password `op://` item references), never keys or tokens.
- A `gitleaks` GitHub Action runs on every push and pull request and is a
  **required status check**; `main` is protected, so nothing lands without a
  clean scan.
- A `gitleaks` pre-commit hook (installed locally via `init.templateDir`)
  catches secrets before they are ever committed. It is bypassable with
  `--no-verify`, so it is the local first line, not the guarantee — the
  required check on protected `main` is the guarantee.
- Anything that has ever been committed to this public repo should be treated
  as compromised and rotated.

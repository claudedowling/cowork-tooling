# cowork-tooling: operating guide

Agent how-to for the Cowork session tooling. Scripts live in `bin/`, deployed read-only from this repo's `main`. This file is the version-controlled source; read it before doing repo or tooling work.

## Session start

1. Connect the tooling folder if it isn't already (its host path is in `config.sh` as `LAPTOP_TOOLING_DIR`).
2. Approve the file-delete tool once, then run `bash <mount>/bin/session-init.sh`. It wires git auth and commit signing, installs the gitleaks pre-commit hook, and mirrors `bin/` from `main`.

## Working with repos

- `bin/use-repo <name> [branch]` is the single front door: clones if absent, fast-forwards if present, checks out a branch. It never merges, forces, or pushes.
- Delete a checkout when done.

## Changing tooling (bin/, workflows, config)

- Never push to the default branch. Branch, commit (signed), open a PR; the owner reviews and it merges.
- A gitleaks pre-commit hook blocks secrets locally; the required gitleaks check plus protected `main` are the real gate. Commits must be signed.
- Never hand-edit the deployed `bin/`; it is a read-only mirror of `main`. Change it via the repo.

## Config and secrets

- Instance settings (git identity, signing item, repo owners) live in a gitignored `config.sh` (`config.example.sh` is the template). Secrets stay in 1Password; scripts hold only `op://` pointers, never secret values.

## Safety invariants

- Do not push to `main` or `master`.
- Do not commit secrets; keep them in 1Password.
- Prefix read-only git with `GIT_OPTIONAL_LOCKS=0` so it never leaves a lock.

# cowork-tooling: operating guide

Agent how-to for the Cowork session tooling. The tooling folder is a clone of this repo's `main`; its tracked files (`bin/`, this file, config template) are kept in sync from GitHub and are not hand-edited. Local-only files (`config.sh`, `.credentials/`, `.op-env`, `repos/`) are gitignored.

## Session start

1. Connect the tooling folder if it isn't already (its host path is in `config.sh` as `LAPTOP_TOOLING_DIR`).
2. Approve the file-delete tool once, then run `bash bin/session-init.sh`. It wires git auth and commit signing, installs the gitleaks pre-commit hook, and syncs the folder to `main`.

## Working with repos

- `bin/use-repo <name> [branch]` is the single front door: clones if absent, fast-forwards if present, checks out a branch. It never merges, forces, or pushes.
- Delete a checkout when done.

## Changing the tooling itself (bin/, workflows, config, this file)

- The tooling folder is pull-only and is reset to `main` each session, so never edit it in place. Make changes in a separate checkout: `bin/use-repo cowork-tooling`, branch, commit (signed), open a PR.
- Never push to the default branch; the owner reviews and it merges. Changes to `bin/`, `.github/`, `.semgrep/`, and `.shellcheckrc` require Code Owner review.
- A gitleaks pre-commit hook blocks secrets locally; the required gitleaks check plus protected `main` are the real gate. Commits must be signed.

## Config and secrets

- Instance settings (git identity, signing item, repo owners) live in a gitignored `config.sh` (`config.example.sh` is the template). Secrets stay in 1Password; scripts hold only `op://` pointers, never secret values.

## Safety invariants

- Do not push to `main` or `master`.
- Do not commit secrets; keep them in 1Password.
- Prefix read-only git with `GIT_OPTIONAL_LOCKS=0` so it never leaves a lock.

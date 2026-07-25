---
title: 'cowork-tooling: architecture and safety model'
tags:
  - cowork
  - tooling
  - architecture
  - security
  - git-workflow
lifecycle: permanent
createdAt: '2026-07-25T03:06:34.072Z'
updatedAt: '2026-07-25T03:06:34.072Z'
role: reference
alwaysLoad: false
project: https-github-com-claudedowling-cowork-tooling
projectName: cowork-tooling
memoryVersion: 1
---
Generic architecture of this repo. Instance-specific values (identity, account names, host paths) live in a gitignored `config.sh` and in the global vault, never here.

## What it is

Session tooling for running Claude Cowork against GitHub from an ephemeral sandbox: a single-token 1Password credential model, a per-session setup script, and a safe front door for cloning/updating repos. The repo is the source of truth; the live `bin/` used in a session is a read-only deployment of `main`.

## bin/ scripts

- `session-init.sh` — run once per session. Sources `config.sh`; wires the git credential helper; sets git identity + SSH commit signing (key read fresh from 1Password to `$HOME/.ssh`, never persisted to the working folder); strips stale per-repo identity overrides; sweeps stale `*.lock` files; installs a pinned gitleaks; seeds a pre-commit hook via `init.templateDir`; deploys `bin/` as a read-only mirror of `main`. Derives the mount from its own location.
- `use-repo` — single front door: clones if absent, fast-forwards if present, checks out an optional branch. Never merges/forces/pushes, never touches uncommitted work. Nudges to set up project memory when a repo lacks `.mnemonic/`.
- `repo-clone`, `repo-latest` — building blocks `use-repo` calls; not invoked directly.
- `gh` — token-injecting wrapper around the real `gh` (kept as `gh-real`).
- `git-credential-op` — git credential helper that resolves the GitHub token from 1Password so plain `git` authenticates with no prefix.
- `op-run.sh` — runs a command with secrets loaded via `op run`.

## Instance config (config.sh, gitignored)

`GIT_USER_NAME`, `GIT_USER_EMAIL`, `SIGNING_OP_ITEM` (op:// ref to the signing SSH key), `REPO_OWNERS` (owner resolution order for bare names), `LAPTOP_TOOLING_DIR` (host path, used in guidance messages), `TOOLING_REPO` (this repo's checkout name). `config.example.sh` is the committed template. Scripts fail loudly if `config.sh` is missing.

## Safety / enforcement

Public repo. A `gitleaks` GitHub Action is a required status check on PRs to `main`. `main` is protected: PR required (0 approvals), required signed commits, force-push and deletion disabled, admin-enforced, auto-merge enabled with branch auto-delete. So `main` — and therefore the deployed `bin/` — only advances via a passing check; nothing lands unsigned or unscanned. The pre-commit template hook is a local first line (bypassable with `--no-verify`); the required check on protected `main` is the guarantee.

Open work: an issue tracks adding a second required check (static analysis / LLM review) that vets `bin/` script changes for harmful behavior, not just secrets.

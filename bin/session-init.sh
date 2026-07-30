#!/usr/bin/env bash
# Cowork session setup. Run once per session, AFTER approving the
# allow_cowork_file_delete tool (the lock sweep below needs it).
#
#   bash <cowork-mount>/bin/session-init.sh
#
# Derives the Cowork mount from its own location, so the changing
# per-session path does not need to be passed in.
set -uo pipefail

M="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Cowork mount: $M"

# Instance configuration (git identity, signing item, repo owners, host path).
# Lives outside the repo so no personal values are committed — see
# config.example.sh. Fail loudly if it is missing.
CONFIG="$M/config.sh"
if [ -f "$CONFIG" ]; then
  . "$CONFIG"
else
  echo "session-init: missing $CONFIG — copy config.example.sh and fill it in" >&2
  exit 1
fi
: "${GIT_USER_NAME:?set it in config.sh}" "${GIT_USER_EMAIL:?set it in config.sh}"
SIGNING_OP_ITEM="${SIGNING_OP_ITEM:-}"
TOOLING_REPO="${TOOLING_REPO:-cowork-tooling}"

# 1. Point git's credential helper at the resolver, so plain `git`
#    clone/fetch/push to GitHub authenticate with no op-run.sh prefix.
#    (The path embeds this session's $M, so it must be set fresh each session.)
echo "== git credential helper =="
for host in github.com gist.github.com; do
  git config --global --unset-all "credential.https://$host.helper" 2>/dev/null
  git config --global --add "credential.https://$host.helper" ""
  git config --global --add "credential.https://$host.helper" "!$M/bin/git-credential-op"
done
echo "configured: github.com, gist.github.com -> git-credential-op"

# 2. Git identity + commit signing. Reads the signing SSH key (SIGNING_OP_ITEM
#    from config.sh) fresh via `op read` and writes the private key to a
#    sandbox-local path OUTSIDE the working folder ($HOME/.ssh, not $M/...), so
#    it is never persisted to the host folder, the same posture as the GitHub
#    token in git-credential-op. It is materialized to a file only because
#    `ssh-keygen -Y sign` (what git's gpg.format=ssh shells out to) needs a
#    file path, not an env var; $HOME is sandbox-local and cleared between
#    sessions, so no explicit cleanup is needed.
#
#    Note: the signing email does not need to be a verified email on the GitHub
#    account for SSH signature verification. That email-matching requirement is
#    GPG-specific, not SSH.
echo "== git identity + commit signing =="
git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"

SSH_DIR="$HOME/.ssh"
SIGNING_KEY="$SSH_DIR/signing-key"
ALLOWED_SIGNERS="$SSH_DIR/allowed_signers"
SIGNING_ITEM="$SIGNING_OP_ITEM"

mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"
export OP_SERVICE_ACCOUNT_TOKEN
OP_SERVICE_ACCOUNT_TOKEN="$(tr -d '\n' < "$M/.credentials/op_token" 2>/dev/null || true)"

# `?ssh-format=openssh` is load-bearing: 1Password's default `private key`
# read for an SSH_KEY item returns PKCS#8 PEM ("-----BEGIN PRIVATE
# KEY-----"), which `ssh-keygen -Y sign` (what git's gpg.format=ssh shells
# out to) rejects with "invalid format". Confirmed by testing both against
# `ssh-keygen -y` this session — PKCS#8 fails to load, OpenSSH format parses
# and derives the expected public key.

if [ -n "$SIGNING_ITEM" ] && [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ] \
   && priv="$("$M/bin/op" read "$SIGNING_ITEM/private key?ssh-format=openssh" 2>/dev/null)" \
   && pub="$("$M/bin/op" read "$SIGNING_ITEM/public key" 2>/dev/null)"; then
  ( umask 077; printf '%s\n' "$priv" > "$SIGNING_KEY" )
  printf '%s\n' "$pub" > "$SIGNING_KEY.pub"
  chmod 600 "$SIGNING_KEY"
  chmod 644 "$SIGNING_KEY.pub"

  git config --global gpg.format ssh
  git config --global user.signingkey "$SIGNING_KEY"
  git config --global commit.gpgsign true
  git config --global tag.gpgsign true

  # Not required for GitHub's own verification, but lets `git log
  # --show-signature` verify locally in this sandbox too.
  printf '%s %s\n' "$GIT_USER_EMAIL" "$pub" > "$ALLOWED_SIGNERS"
  git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"

  echo "configured: commit.gpgsign=true, signing key from 1Password (fingerprint below)"
  "$M/bin/op" read "$SIGNING_ITEM/fingerprint" 2>/dev/null || true
else
  echo "WARNING: could not fetch signing key from 1Password ($SIGNING_ITEM) — commits will be unsigned this session" >&2
  git config --global --unset commit.gpgsign 2>/dev/null || true
fi
unset OP_SERVICE_ACCOUNT_TOKEN priv pub

# 3. Already-cloned repos can carry a stale LOCAL user.name/user.email that
#    would silently override the global identity set above. Strip local
#    overrides so the global identity always wins; repo-local commit.gpgsign
#    overrides are left alone in case a repo deliberately opts out.
echo "== clearing stale per-repo git identity overrides =="
shopt -s nullglob
for d in "$M"/repos/*/; do
  [ -d "$d/.git" ] || continue
  before="$(git -C "$d" config --local --get user.email 2>/dev/null || true)"
  if [ -n "$before" ]; then
    git -C "$d" config --local --unset-all user.name 2>/dev/null || true
    git -C "$d" config --local --unset-all user.email 2>/dev/null || true
    echo "$(basename "$d"): cleared local override (was $before)"
  fi
done

# 4. Sweep stale git lock files left by a prior session.
#    Requires allow_cowork_file_delete approved this session, else the
#    rm fails with "Operation not permitted" (the errors are harmless).
echo "== stale lock sweep =="
mapfile -t locks < <(find "$M/repos" -path '*/.git/*' -name '*.lock' 2>/dev/null)
if [ "${#locks[@]}" -gt 0 ]; then
  printf 'clearing: %s\n' "${locks[@]}"
  rm -f "${locks[@]}"
else
  echo "none"
fi

# 5. Report each repo's state, read-only. GIT_OPTIONAL_LOCKS=0 means these
#    checks never create a lock themselves.
echo "== repo state =="
found=0
for d in "$M"/repos/*/; do
  [ -d "$d/.git" ] || continue
  found=1
  printf '%-28s ' "$(basename "$d")"
  GIT_OPTIONAL_LOCKS=0 git -C "$d" status -sb 2>&1 | head -1
done
[ "$found" -eq 0 ] && echo "(no repos cloned yet)"

# 6. Secret scanning. Install a pinned gitleaks and seed a pre-commit hook.
#    The hook is a local first line only (bypassable with --no-verify); the
#    real guarantee is the required "gitleaks" status check on this repo's
#    protected main. The hook resolves gitleaks relative
#    to the repo's own location (checkouts live at <mount>/repos/<name>, so
#    ../../bin/gitleaks is this mount's copy), so it survives the per-session
#    mount path changing without being rewritten.
echo "== secret scanning (gitleaks) =="
GITLEAKS_VERSION=8.18.4
GL="$M/bin/gitleaks"
if [ -x "$GL" ] && "$GL" version 2>/dev/null | grep -qx "$GITLEAKS_VERSION"; then
  echo "gitleaks $GITLEAKS_VERSION present"
else
  gl_url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
  if curl -sSL "$gl_url" | tar -xz -C "$M/bin" gitleaks 2>/dev/null && [ -x "$GL" ]; then
    chmod +x "$GL"; echo "installed gitleaks $GITLEAKS_VERSION"
  else
    echo "WARNING: could not install gitleaks from $gl_url — pre-commit scanning unavailable" >&2
  fi
fi

TMPL="$M/.githooks-template/hooks"
mkdir -p "$TMPL"
cat > "$TMPL/pre-commit" <<'HOOK'
#!/bin/sh
# Block commits that contain secrets (gitleaks). Local first line only,
# bypassable with --no-verify. gitleaks is resolved relative to the repo:
# checkouts live at <mount>/repos/<name>, so ../../bin/gitleaks is this
# mount's copy. No session path is hardcoded.
repo="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
gl="$repo/../../bin/gitleaks"
if [ ! -x "$gl" ]; then
  echo "pre-commit: gitleaks not found at $gl (run session-init.sh); refusing commit" >&2
  exit 1
fi
exec "$gl" protect --staged --redact --no-banner
HOOK
chmod +x "$TMPL/pre-commit"
git config --global init.templateDir "$M/.githooks-template"
echo "pre-commit template installed (init.templateDir)"

# Backfill: checkouts cloned before the template existed have no hook. Seed
# only where absent so a repo's own pre-commit is never clobbered.
for d in "$M"/repos/*/; do
  [ -d "$d/.git" ] || continue
  if [ ! -e "$d/.git/hooks/pre-commit" ]; then
    cp "$TMPL/pre-commit" "$d/.git/hooks/pre-commit" && chmod +x "$d/.git/hooks/pre-commit"
    echo "  seeded pre-commit in $(basename "$d")"
  fi
done

echo "== done. Reminder: prefix read-only git with GIT_OPTIONAL_LOCKS=0; branch + PR, never push to the default branch. =="

# 7. Keep the tooling folder a clean, pull-only clone of main. The folder root
#    is a checkout of this repo; tracked files (bin/, CLAUDE.md, ...) are
#    updated only from GitHub, never hand-edited. Gitignored local files
#    (config.sh, .credentials/, .op-env, repos/) are left untouched by the
#    reset. Edit the tooling via a separate checkout under repos/
#    (use-repo cowork-tooling), branch + PR.
#
#    This runs LAST: reset --hard rewrites tracked files including this running
#    script, so the reset and exit are one already-parsed line and nothing
#    executes after it.
echo "== sync tooling folder to main =="
if ! git -C "$M" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "tooling folder is not a git clone; skipping sync (run the one-time clone conversion)" >&2
elif ! git -C "$M" fetch -q origin main 2>/dev/null; then
  echo "fetch failed; folder not synced (offline?)" >&2
else
  b="$(GIT_OPTIONAL_LOCKS=0 git -C "$M" rev-parse --short HEAD)"
  a="$(GIT_OPTIONAL_LOCKS=0 git -C "$M" rev-parse --short origin/main)"
  [ "$b" = "$a" ] && echo "already at $a" || echo "syncing $b -> $a"
  git -C "$M" reset --hard origin/main >/dev/null 2>&1; exit 0
fi

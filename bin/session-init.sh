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

# 2. Git identity + commit signing. Fetches the "SSH Key - claudedowling -
#    Github" item (Claude Code vault, category SSH_KEY) fresh via `op read`
#    and writes the private key to a sandbox-local path OUTSIDE the Cowork
#    mount ($HOME/.ssh, not $M/...), so it's never persisted to the laptop
#    folder — same never-touches-disk-long-term posture as GH_TOKEN in
#    git-credential-op, just materialized to a file because `ssh-keygen -Y
#    sign` (what git's gpg.format=ssh shells out to) needs a file path, not
#    an env var. $HOME is sandbox-local and cleared between sessions per the
#    Cowork environment notes, so this doesn't need explicit cleanup.
#
#    Identity: name "claudedowling" (matches the GitHub account the token
#    authenticates as), email "claude@dowling.co.nz" (does not need to be a
#    verified email on the account for SSH signature verification — that
#    email-matching requirement is GPG-specific, not SSH; see GitHub's
#    commit-signature-verification troubleshooting docs, which file "use a
#    verified email in your GPG key" under GPG only).
echo "== git identity + commit signing =="
git config --global user.name "claudedowling"
git config --global user.email "claude@dowling.co.nz"

SSH_DIR="$HOME/.ssh"
SIGNING_KEY="$SSH_DIR/claudedowling-signing"
ALLOWED_SIGNERS="$SSH_DIR/allowed_signers"
SIGNING_ITEM="op://Claude Code/SSH Key - claudedowling - Github"

mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"
export OP_SERVICE_ACCOUNT_TOKEN
OP_SERVICE_ACCOUNT_TOKEN="$(tr -d '\n' < "$M/.credentials/op_token" 2>/dev/null || true)"

# `?ssh-format=openssh` is load-bearing: 1Password's default `private key`
# read for an SSH_KEY item returns PKCS#8 PEM ("-----BEGIN PRIVATE
# KEY-----"), which `ssh-keygen -Y sign` (what git's gpg.format=ssh shells
# out to) rejects with "invalid format". Confirmed by testing both against
# `ssh-keygen -y` this session — PKCS#8 fails to load, OpenSSH format parses
# and derives the expected public key.

if [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ] \
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
  printf '%s %s\n' "claude@dowling.co.nz" "$pub" > "$ALLOWED_SIGNERS"
  git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"

  echo "configured: commit.gpgsign=true, signing key from 1Password (fingerprint below)"
  "$M/bin/op" read "$SIGNING_ITEM/fingerprint" 2>/dev/null || true
else
  echo "WARNING: could not fetch signing key from 1Password ($SIGNING_ITEM) — commits will be unsigned this session" >&2
  git config --global --unset commit.gpgsign 2>/dev/null || true
fi
unset OP_SERVICE_ACCOUNT_TOKEN priv pub

# 3. Already-cloned repos can carry a stale LOCAL user.name/user.email that
#    would silently override the global identity just set above (nas-docker
#    had one: claudedowling <claudedowling@users.noreply.github.com>, set by
#    an earlier session before this script managed identity). Strip local
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

echo "== done. Reminder: prefix read-only git with GIT_OPTIONAL_LOCKS=0; branch + PR, never push to the default branch. =="

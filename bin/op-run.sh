#!/bin/sh
# Wrapper to run a command with secrets loaded from 1Password via a
# service account, using the stable (GA) `op run` mechanism — not the
# beta Environments feature, which this CLI build doesn't support.
#
# Usage:
#   op-run.sh <command> [args...]
#
# Requires:
#   $M/.credentials/op_token   - service account token (plaintext, one line)
#   $M/.op-env                 - .env-style file of secret references, e.g.:
#                                   GH_TOKEN=op://Claude Code/github/token
#
# Secrets are only exposed in the environment of the subprocess this
# script execs; they're never written to disk here.

set -eu

M="$(cd "$(dirname "$0")/.." && pwd)"

TOKEN_FILE="$M/.credentials/op_token"
ENV_FILE="$M/.op-env"
OP_BIN="$M/bin/op"

if [ ! -f "$TOKEN_FILE" ]; then
  echo "op-run.sh: missing $TOKEN_FILE" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "op-run.sh: missing $ENV_FILE (create it with op:// secret references)" >&2
  exit 1
fi

export OP_SERVICE_ACCOUNT_TOKEN
OP_SERVICE_ACCOUNT_TOKEN="$(tr -d '\n' < "$TOKEN_FILE")"

exec "$OP_BIN" run --env-file="$ENV_FILE" -- "$@"

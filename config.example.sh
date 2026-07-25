# cowork-tooling instance configuration.
#
# Copy this to a file named `config.sh` in your Cowork working folder (the
# parent of bin/), and fill in your own values. config.sh is gitignored — it
# holds machine/account-specific settings and never belongs in the repo.
#
#   cp config.example.sh /path/to/your/cowork-folder/config.sh

# Git identity for commits made during sessions.
GIT_USER_NAME="Your Name"
GIT_USER_EMAIL="you@example.com"

# 1Password reference (op://vault/item) for the SSH key used to sign commits.
# Leave empty to skip commit signing entirely.
SIGNING_OP_ITEM="op://YourVault/Your SSH Signing Key"

# GitHub owners that a bare repo name is resolved against, in priority order
# (space-separated). Used by repo-clone/use-repo.
REPO_OWNERS="your-github-user"

# Absolute path to this tooling folder on the host. Used only in guidance
# messages printed to the agent (e.g. the mnemonic project-memory nudge).
LAPTOP_TOOLING_DIR="/path/to/cowork-tooling"

# Name of this tooling repo's checkout under repos/ (used by the read-only
# bin deploy). Only change this if you fork and rename the repo.
TOOLING_REPO="cowork-tooling"

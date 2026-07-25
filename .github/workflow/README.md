# Staged workflows: `bin/` harmful-behavior check

Implements the recommendation from [issue #3](../../issues/3): a second
required status check, alongside `gitleaks`, that reviews changes to `bin/`
for harmful behavior (not just secrets) before they can merge to `main`.

These three files are staged here instead of `.github/workflows/` because
the bot that opened this PR doesn't have `workflow` scope and can't write
there. They need a human with that scope to move them into place.

## What's here

| File | Layer | What it catches |
|------|-------|------------------|
| `shellcheck.yml` | correctness | Quoting bugs, unsafe word-splitting, unsafe `eval` — footguns, not malice, but cheap and free of false positives. |
| `semgrep.yml` | deterministic security floor | Piped-remote-exec, raw `eval` of input, `rm -rf` on a variable, a token variable next to a network call, base64-decode-into-shell. Ruleset is `.semgrep/bin-security.yml`, written against this repo's actual risk patterns rather than generic community rules. |
| `bin-security-review.yml` | semantic security review | A narrow Claude prompt scoped only to `bin/**` diffs, asking specifically about exfiltration, credential misuse, destructive ops, obfuscation, and trust-boundary tampering (e.g. a `git-credential-op` that now also POSTs the token somewhere). This is the layer that can catch a *plausible-looking* malicious change that a linter or regex can't, since it reasons about intent. |

None of the three are a full substitute for the others — see the research
comment on issue #3 for the tradeoffs of each layer individually.

## Activation steps

1. **Move the files**: `git mv .github/workflow-proposals/*.yml .github/workflows/` (leave `.semgrep/bin-security.yml` and `.shellcheckrc` where they are — those are final locations already, not staged).
2. **Verify pinned versions still exist and are current**: this PR was authored without outbound network access to verify releases, so `shellcheck.yml` pins ShellCheck `v0.9.0` and `semgrep.yml` allows `semgrep>=1.70.0,<2.0.0` rather than an exact version. Before relying on this as a required check, bump ShellCheck to the current release and pin Semgrep to an exact, verified version (`pip install semgrep==<version>`) for reproducibility.
3. **Add the `CLAUDE_CODE_OAUTH_TOKEN` secret** if `bin-security-review.yml` will use a different token/scope than the existing `claude.yml`/`claude-code-review.yml` workflows — otherwise it already exists in this repo's secrets.
4. **Dry-run before making it required**: open a few real and a few intentionally-benign PRs touching `bin/` and watch `bin-security-review.yml`'s false-positive rate. The issue explicitly calls out that a noisy check trains people to ignore it — tune the prompt in `bin-security-review.yml` (and the regexes in `../../.semgrep/bin-security.yml`) until it's quiet on normal changes.
5. **Add all three as required status checks** on `main` (Settings → Branches → branch protection rule for `main` → Require status checks to pass → add `shellcheck`, `semgrep (bin/ custom ruleset)`, `claude security review (bin/)` by their job names).
6. **Turn on "Require review from Code Owners"** in the same branch protection rule, so `../CODEOWNERS` (added in this PR) actually gates changes to `bin/**` and `.github/workflows/**` — this is what stops a PR from weakening its own gate, per the issue's third acceptance criterion.
7. **SHA-pin `actions/checkout@v4` and `anthropics/claude-code-action@v1`** in these three files (and, ideally as a follow-up, in the existing `gitleaks.yml`/`claude.yml`/`claude-code-review.yml`) once moved — floating tags are the one piece of this PR that couldn't be hardened without network access to look up current commit SHAs.
8. **Delete this folder** once the files are moved and working.

#!/usr/bin/env bash
# §4.4 Pattern D — Workflow Precheck (WPC) — standalone precheck script
#
# This script extracts the precheck-step bash logic from the canonical
# reference workflow at:
#   groundnuty/macf-devops-toolkit:.github/workflows/observability-snapshot.yml
# (Step: "Precheck — required secrets + variables present", lines ~39-60.)
#
# The canonical step uses GitHub Actions ${{ secrets.X }} substitution to
# bind 4 secrets + 1 variable into env vars, then aggregates ALL missing
# names into a single ::error:: block before exit 1. This standalone form
# preserves the same logic verbatim, with required-input names parameterized
# via the REQUIRED env var (or hardcoded default for the canonical 5-input
# observability-snapshot set).
#
# This is approach (a) from the pre-reg: literal copy of the canonical
# precheck-step bash, parameterized for harness use. Tests the actual
# deployed implementation, not a clean re-write.
#
# Pre-reg: appendix/A5-failure-injection.md §"Pattern D"
# Pre-reg commit: 25c08da (feat/paper-attribution-validation)
#
# Usage:
#   REQUIRED="VAR1:secret VAR2:variable VAR3:secret" \
#     VAR1="..." VAR2="..." VAR3="..." \
#     bash precheck.sh
#
#   The REQUIRED list is space-separated "<NAME>:<kind>" tokens. <kind> is
#   "secret" or "variable" (used only in the error annotation). Each token
#   declares one required input that must be set + non-empty in the env.
#
# If REQUIRED is not set, the script uses the canonical 5-input default
# matching observability-snapshot.yml (TAILSCALE_OAUTH_CLIENT_ID + 3 more
# secrets + OBS_RUNNER_HOST variable).
#
# Output:
#   - On all-present:  exit 0; "✓ All N inputs present" to stdout
#   - On any missing:  exit 1; ::error::Missing required workflow inputs:
#                      then ::error::  - <NAME> (<kind>) per missing,
#                      then ::error::See <runbook>... reference.

set -euo pipefail

# Default REQUIRED matches the canonical observability-snapshot.yml step.
# Override via REQUIRED env var for harness trials.
REQUIRED="${REQUIRED:-TAILSCALE_OAUTH_CLIENT_ID:secret TAILSCALE_OAUTH_SECRET:secret OBS_RUNNER_SSH_KEY:secret ARCHIVE_DEPLOY_KEY:secret OBS_RUNNER_HOST:variable}"

# Runbook reference — canonical line is "See docs/observability-bundle-setup.md
# for the runbook." Keep that exact string for harness assertions.
RUNBOOK="${RUNBOOK:-docs/observability-bundle-setup.md}"

missing=()

# Parse REQUIRED tokens; for each, check the env var by name and aggregate
# missing entries into the error block. This mirrors the canonical step's
# `[ -z "${VAR:-}" ] && missing+=("VAR (kind)")` pattern, but loops over
# the REQUIRED list so the harness can vary inputs per trial.
for token in $REQUIRED; do
  name="${token%%:*}"
  kind="${token##*:}"
  # ${!name:-} is bash indirect expansion: value of the env var named by $name,
  # defaulting to empty if unset. Treats unset and empty-string identically,
  # matching the canonical step's behavior (GitHub Actions substitutes both
  # missing-secret and empty-secret as empty-string at substitution time).
  if [ -z "${!name:-}" ]; then
    missing+=("$name ($kind)")
  fi
done

if [ ${#missing[@]} -gt 0 ]; then
  echo "::error::Missing required workflow inputs:"
  for m in "${missing[@]}"; do
    echo "::error::  - $m"
  done
  echo "::error::See $RUNBOOK for the runbook."
  exit 1
fi

# All-present path: emit the canonical success line. Count is dynamic
# (the canonical "✓ All 4 secrets + 1 variable present" is hardcoded for
# the 5-input set; here we generalize).
n=$(echo $REQUIRED | wc -w)
echo "✓ All $n inputs present"
exit 0

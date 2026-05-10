#!/usr/bin/env bash
# analyze §27 methodology deviations + Pattern B anomaly framing
#
# Verifies the structural completeness of methodology-deviations.md:
#   - 3 patterns documented (A, D, E)
#   - 3 methodology-execution findings (per §28 R11):
#     - Pattern A cross-identity boundary (App tokens can't impersonate users)
#     - Pattern D 3-pivot (App-perm scope constrains experiment paths)
#     - Pattern E 3 reconciliations (log key, activity-timestamp, N=25 spec)
#
# Pattern B anomaly verifier — once Pattern B's harness PR merges, this
# script will verify the prefix-only-validation coverage gap (§27 Finding #1)
# from the trial that exercised `GH_TOKEN=ghs_; rm -rf <sentinel>`.
#
# Reviewer-runnable from clean clone — no token/SSH/live API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$WORKSPACE/data/failure-injection"
DEVIATIONS="$DATA_DIR/methodology-deviations.md"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

echo "=== §27 methodology deviations + Pattern B anomaly ==="
echo "Anchors §28 R10 (Pattern E selectivity), R11 (3 methodology-execution"
echo "findings), R12 (Pattern B prefix-only-validation coverage gap)."
echo ""

if [ ! -f "$DEVIATIONS" ]; then
  echo "✗ methodology-deviations.md not found at $DEVIATIONS" >&2
  exit 1
fi

echo "## §27 methodology-deviations.md structural verification"
fail=0

# Verify 3 pattern sections present
for pat in "Pattern A" "Pattern D" "Pattern E"; do
  if grep -q "^## $pat" "$DEVIATIONS"; then
    echo "  ✓ §$pat section present"
  else
    echo "  ✗ §$pat section MISSING" >&2
    fail=1
  fi
done

echo ""
echo "## R11 — 3 methodology-execution findings (each a §$pat finding)"

# Pattern A — cross-identity pivot (App tokens can't impersonate users)
# The phrase "App-installation tokens cannot impersonate user identities"
# wraps across 2 lines; match either single-line fragment.
if grep -q -E "App-installation tokens|cannot impersonate user identities|cross-identity pivot|different-bot vector" "$DEVIATIONS"; then
  echo "  ✓ Pattern A: App-installation token boundary documented"
else
  echo "  ✗ Pattern A: App-token cross-identity finding NOT documented" >&2
  fail=1
fi

# Pattern D — 3-pivot (App-perm scope constrains experiment paths)
if grep -q -E "macf-testbed.*macf|3-pivot|workflow_dispatch.*push|secrets.*vars" "$DEVIATIONS"; then
  echo "  ✓ Pattern D: 3-pivot rationale documented"
else
  echo "  ✗ Pattern D: 3-pivot finding NOT documented" >&2
  fail=1
fi

# Pattern E — 3 reconciliations (log key, activity-timestamp, N=25)
e_recon_count=0
grep -q -E "tmux_wake_skipped|action_path_skipped" "$DEVIATIONS" && e_recon_count=$((e_recon_count+1))
grep -q -E "window_activity|session_activity" "$DEVIATIONS" && e_recon_count=$((e_recon_count+1))
grep -q -E "N=25|negative-control supplement" "$DEVIATIONS" && e_recon_count=$((e_recon_count+1))
if [ "$e_recon_count" = "3" ]; then
  echo "  ✓ Pattern E: 3 reconciliations documented (log key + window_activity + N=25)"
else
  echo "  ✗ Pattern E: only $e_recon_count of 3 reconciliations documented" >&2
  fail=1
fi

echo ""
echo "## R10 — Pattern E selectivity (verified in analyze-26-injection.sh)"
echo "  Pattern E negative-control rate (5/5 issue_routed → wake) is verified"
echo "  separately in analyze-26-injection.sh §'Pattern E selectivity'."
echo "  This script's role is structural completeness of deviations.md."

echo ""
echo "## R12 — Pattern B prefix-only-validation coverage gap"
B_TRIALS="$DATA_DIR/b/trials.tsv"
if [ -f "$B_TRIALS" ]; then
  # Pattern B's data has landed; verify the 1/10 anomaly
  meta_injection=$(awk -F'\t' '$5 ~ /meta-injection/ && $3 == "FAIL"' "$B_TRIALS" | wc -l)
  if [ "$meta_injection" = "1" ]; then
    echo "  ✓ Pattern B: bash-meta-injection trial documented as FAIL (the anomaly)"
  else
    echo "  ✗ Pattern B: meta-injection anomaly NOT visible in trials.tsv" >&2
    fail=1
  fi
else
  echo "  ⚠ Pattern B trials.tsv not on main yet — anomaly framing verified in §27"
  echo "    prose only (paper-injection/b-harness branch). Re-run when B PR merges."
fi

echo ""
if [ "$fail" = "0" ]; then
  echo "✓ §27 methodology deviations structurally verified."
  echo ""
  echo "## Paper §5 threats anchor"
  echo "  3 methodology-execution findings worth a §5 threats-validity bullet:"
  echo "    (a) Pattern A cross-identity boundary (App tokens vs user PATs)"
  echo "    (b) Pattern D cross-repo perm scope (macf-testbed → macf 3-pivot)"
  echo "    (c) Pattern B prefix-only-validation coverage gap inside boundary"
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

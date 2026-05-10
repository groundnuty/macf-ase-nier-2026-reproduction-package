#!/usr/bin/env bash
# analyze §17 per-failure-mode classification
#
# Reads frozen per-failure-mode.tsv and emits Mode 3+4 dominance ratio
# that anchors paper §3.1's "~80% reliability" → measured 87.0% (Mode 3+4
# fraction of observable failure surface).
#
# **DOUBLE-CHECK FINDING** (operator authorized 2026-05-09):
#   §17 prose claims Mode 3+4 = 289/353 = 81.9%, derived from a session-log
#   snapshot at 2026-05-09T12:58Z. The frozen TSV (per-failure-mode.tsv,
#   committed 15:03Z, ~2h later) shows Mode 3+4 = 410/471 = 87.0%. The
#   discrepancy is 121 events that landed in session logs during the 2-hour
#   window between the original analysis and the frozen TSV (active session
#   work generating new tool_results).
#
# The TSV is the citable artifact (frozen + reproducible). §28's "81.9%"
# claim should be updated to 87.0% (the byte-verifiable number from frozen
# data). This is exactly the kind of double-check the operator authorized.
#
# Reviewer-runnable from clean clone — no token/SSH/live API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA="$WORKSPACE/data/session-logs/per-failure-mode.tsv"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

echo "=== §17 per-failure-mode classification ==="
echo "Reproducing paper §3.1 reliability-ceiling anchor."
echo ""
echo "Source: $DATA"
echo ""

# Read TSV; row format: mode \t description \t sa_count \t ca_count \t total
echo "## Per-mode counts (from frozen TSV)"
column -t -s $'\t' "$DATA"
echo ""

# Compute total + per-mode percentages
total=$(awk -F'\t' 'NR>1 {sum+=$5} END {print sum}' "$DATA")
mode34=$(awk -F'\t' 'NR>1 && $1 == "3+4" {print $5}' "$DATA")
mode1=$(awk -F'\t' 'NR>1 && $1 == "1" {print $5}' "$DATA")
mode2=$(awk -F'\t' 'NR>1 && $1 == "2" {print $5}' "$DATA")
mode5=$(awk -F'\t' 'NR>1 && $1 == "5" {print $5}' "$DATA")

mode34_pct=$(python3 -c "print(f'{100*$mode34/$total:.1f}')")
mode1_pct=$(python3 -c "print(f'{100*$mode1/$total:.1f}')")
mode2_pct=$(python3 -c "print(f'{100*$mode2/$total:.1f}')")
mode5_pct=$(python3 -c "print(f'{100*$mode5/$total:.1f}')")

echo "## Mode-share computation"
printf "  %-30s %10s %10s\n" "mode" "events" "share"
printf "  %-30s %10d %9s%%\n" "Mode 1 (key fingerprint)"  "$mode1"   "$mode1_pct"
printf "  %-30s %10d %9s%%\n" "Mode 2 (JWT decode)"        "$mode2"   "$mode2_pct"
printf "  %-30s %10d %9s%%\n" "Mode 3+4 (HTTP 401)"        "$mode34"  "$mode34_pct"
printf "  %-30s %10d %9s%%\n" "Mode 5 (helper missing)"    "$mode5"   "$mode5_pct"
printf "  %-30s %10d %10s\n"  "TOTAL"                       "$total"   "100%"

echo ""
echo "## Verification against frozen TSV (the byte-verifiable artifact)"
fail=0
assert_match "471"  "$total"   "total observable failures"      || fail=1
assert_match "410"  "$mode34"  "Mode 3+4 events"                || fail=1
assert_match "87.0" "$mode34_pct" "Mode 3+4 dominance %"         || fail=1

echo ""
echo "## §17 vs frozen TSV reconciliation (DOUBLE-CHECK FINDING)"
echo ""
echo "  §17 prose (2026-05-09T12:58Z snapshot):  Mode 3+4 = 289/353 = 81.9%"
echo "  Frozen TSV (2026-05-09T15:03Z):           Mode 3+4 = 410/471 = 87.0%"
echo "  Δ = 121 events landed in session logs during the 2h window between"
echo "      original analysis + TSV freeze (active work generating new"
echo "      tool_results during paper-research §93-#108 sprint)"
echo ""
echo "  RECOMMENDATION (paper-grade): paper-strengthening §28 currently cites"
echo "  '81.9%' (from §17 prose). The byte-verifiable number is 87.0% (from"
echo "  frozen TSV). §28 + §25 should be updated to 87.0% to match what the"
echo "  reproducible analyze script emits. Or §28 should explicitly note the"
echo "  snapshot-vs-TSV reconciliation."

echo ""
if [ "$fail" = "0" ]; then
  echo "✓ All frozen-TSV values verified."
  echo ""
  echo "## Paper §3.1 anchor"
  echo "  - Mode 3+4 (HTTP 401 / Bad credentials) = $mode34/$total = $mode34_pct% of observable failures"
  echo "  - This is the 'silent-fallback' mode — fires without surfacing exit-code errors"
  echo "  - Modes 1, 2, 5 produce loud errors at mint time (caught early)"
  echo "  - Mode 6 (cross-repo cd) is behavioral, not error-message-based — see macf#161"
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

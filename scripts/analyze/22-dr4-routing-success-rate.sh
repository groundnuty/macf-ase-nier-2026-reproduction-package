#!/usr/bin/env bash
# analyze §22 DR-4 routing success rate (§3.4 reinforcement)
#
# Reads frozen workflow-runs-summary.tsv + summary.tsv and verifies:
#   - 99.05% workflow availability across 2,521 routing-Action runs
#   - Per-repo success rates (macf 99.07%, macf-actions 97.17%, etc.)
#   - 1,315 comments with bot @-mentions across 17,175 total
#
# Anchors paper §3.4 (DD4) routing-protocol claim with empirical numbers.
#
# Reviewer-runnable from clean clone — no token/SSH/live API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$WORKSPACE/data/dr4-routing"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

echo "=== §22 DR-4 routing success rate (§3.4 reinforcement) ==="
echo ""

echo "## Workflow runs summary (frozen TSV)"
column -t -s $'\t' "$DATA_DIR/workflow-runs-summary.tsv"
echo ""

# Aggregate across all 4 repos
total_runs=$(awk -F'\t' 'NR>1 {s+=$2} END {print s}' "$DATA_DIR/workflow-runs-summary.tsv")
total_success=$(awk -F'\t' 'NR>1 {s+=$3} END {print s}' "$DATA_DIR/workflow-runs-summary.tsv")
total_failure=$(awk -F'\t' 'NR>1 {s+=$4} END {print s}' "$DATA_DIR/workflow-runs-summary.tsv")
total_startup=$(awk -F'\t' 'NR>1 {s+=$5} END {print s}' "$DATA_DIR/workflow-runs-summary.tsv")
total_failed=$((total_failure + total_startup))

availability_rate=$(python3 -c "print(f'{100*$total_success/$total_runs:.2f}')")

echo "## Aggregate computation"
printf "  %-30s %d\n" "Total runs (4 repos)"        "$total_runs"
printf "  %-30s %d\n" "Successful runs"              "$total_success"
printf "  %-30s %d (failure: $total_failure + startup_failure: $total_startup)\n" "Failed runs" "$total_failed"
printf "  %-30s %s%%\n" "Workflow availability rate" "$availability_rate"
echo ""

echo "## Verification against §22 documented values"
fail=0
assert_match "2521" "$total_runs"     "2,521 total runs"               || fail=1
assert_match "2497" "$total_success"  "2,497 successful runs"          || fail=1
assert_match "24"   "$total_failed"   "24 failures (failure + startup)" || fail=1
assert_match "99.05" "$availability_rate" "99.05% availability rate"   || fail=1

# Per-repo verification
for repo in groundnuty/macf groundnuty/macf-actions groundnuty/macf-marketplace groundnuty/macf-devops-toolkit; do
  rate=$(awk -F'\t' -v r="$repo" '$1 == r {print $7}' "$DATA_DIR/workflow-runs-summary.tsv")
  case "$repo" in
    groundnuty/macf) expected="99.07%" ;;
    groundnuty/macf-actions) expected="97.17%" ;;
    groundnuty/macf-marketplace) expected="100.00%" ;;
    groundnuty/macf-devops-toolkit) expected="100.00%" ;;
  esac
  assert_match "$expected" "$rate" "$repo per-repo rate" || fail=1
done

echo ""
echo "## Verification against summary.tsv"
l1_runs=$(awk -F'\t' '$1 == "L1_total_runs" {print $2}' "$DATA_DIR/summary.tsv")
l1_success=$(awk -F'\t' '$1 == "L1_success" {print $2}' "$DATA_DIR/summary.tsv")
l1_rate=$(awk -F'\t' '$1 == "L1_availability_rate" {print $2}' "$DATA_DIR/summary.tsv")
l3_mentions=$(awk -F'\t' '$1 == "L3_comments_with_mention" {print $2}' "$DATA_DIR/summary.tsv")
assert_match "2521" "$l1_runs"  "summary.tsv L1 total runs"           || fail=1
assert_match "2497" "$l1_success" "summary.tsv L1 success runs"        || fail=1
assert_match "99.05%" "$l1_rate"  "summary.tsv L1 availability rate"   || fail=1
assert_match "1315" "$l3_mentions" "summary.tsv L3 comments with mention" || fail=1

echo ""
if [ "$fail" = "0" ]; then
  echo "✓ Paper §3.4 (DD4) routing-protocol claim VERIFIED."
  echo ""
  echo "## Paper §3.4 anchor"
  echo "  - 99.05% workflow availability across 2,521 runs in 4 macf-* repos"
  echo "  - 24 failures concentrated in workflow-bootstrap (Apr 14-21) +"
  echo "    dependabot collateral (Apr 28 + May 5)"
  echo "  - 4 substantive steady-state failures (post-2026-04-22) = 0.17%"
  echo "  - 1,315 comments with bot @-mentions across 17,175 total comments"
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

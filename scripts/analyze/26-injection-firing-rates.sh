#!/usr/bin/env bash
# analyze §27 failure-injection firing rates (paper §4.4 fill)
#
# Reads frozen per-pattern trials.tsv files + firing-counts.tsv, recomputes
# K/N + Wilson 95% lower CI for each pattern, and verifies match against
# §27's documented values. Emits §4.4 paste-ready table.
#
# Per-pattern trial schemas differ — handled per pattern:
#   - A: trial_n  outcome  duration_ms  details
#        outcome col = 2 (PASS / FAIL)
#   - C: trial_n  outcome  duration_ms  session_name  pre  post  details
#        outcome col = 2
#   - D: trial_n  variant  subcategory  outcome  duration_ms  missing_names  details
#        outcome col = 4
#   - E: trial_n  notify_type  outcome  mcp_pushed  wake_skipped  duration_ms  details
#        outcome col = 3
#   - B: NOT YET ON MAIN (code-agent's paper-injection/b-harness branch).
#        Documented values: K/N = 9/10 (Wilson 95% lower 59.6%); 1 anomaly
#        (prefix-only-validation coverage gap). Hardcoded expected; verifier
#        skipped until B PR merges.
#
# Reviewer-runnable from clean clone — no token/SSH/live API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$WORKSPACE/data/failure-injection"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

# Pattern → outcome column index in trials.tsv
declare -A OUTCOME_COL
OUTCOME_COL[a]=2
OUTCOME_COL[c]=2
OUTCOME_COL[d]=4
OUTCOME_COL[e]=3

count_passes() {
  local letter="$1"
  local file="$DATA_DIR/$letter/trials.tsv"
  local col="${OUTCOME_COL[$letter]}"
  if [ ! -f "$file" ]; then echo "0 0"; return; fi
  local total pass
  total=$(awk 'NR>1' "$file" | wc -l)
  pass=$(awk -F'\t' -v c="$col" 'NR>1 && $c == "PASS"' "$file" | wc -l)
  echo "$pass $total"
}

echo "=== Failure-injection firing rates ==="
echo "Reproducing the per-pattern firing counts reported in paper §4.4."
echo ""

echo "## Per-pattern verification (K/N from trials.tsv vs reported in A5)"
printf "  %-9s %12s %12s %20s %12s\n" "pattern" "K (computed)" "N (computed)" "Wilson 95% lower" "documented"
fail=0

# Pattern A
read -r ka na <<< "$(count_passes a)"
wa="$(wilson_lower_95 "$ka" "$na")"
printf "  %-9s %12d %12d %19s%% %12s\n" "A (RIA)" "$ka" "$na" "$wa" "20/20 → 83.9%"
assert_match "20" "$ka" "Pattern A K=20" || fail=1
assert_match "20" "$na" "Pattern A N=20" || fail=1
assert_match "83.9" "$wa" "Pattern A Wilson 83.9%" || fail=1

# Pattern B (NOT IN MAIN — documented expected)
echo "  B (PFV)         9          10           59.6%* 9/10 → 59.6% [B harness on paper-injection/b-harness; not yet merged]"

# Pattern C
read -r kc nc <<< "$(count_passes c)"
wc_c="$(wilson_lower_95 "$kc" "$nc")"
printf "  %-9s %12d %12d %19s%% %12s\n" "C (HB)" "$kc" "$nc" "$wc_c" "20/20 → 83.9%"
assert_match "20" "$kc" "Pattern C K=20" || fail=1
assert_match "20" "$nc" "Pattern C N=20" || fail=1
assert_match "83.9" "$wc_c" "Pattern C Wilson 83.9%" || fail=1

# Pattern D
read -r kd nd <<< "$(count_passes d)"
wd="$(wilson_lower_95 "$kd" "$nd")"
printf "  %-9s %12d %12d %19s%% %12s\n" "D (WPC)" "$kd" "$nd" "$wd" "20/20 → 83.9%"
assert_match "20" "$kd" "Pattern D K=20" || fail=1
assert_match "20" "$nd" "Pattern D N=20" || fail=1
assert_match "83.9" "$wd" "Pattern D Wilson 83.9%" || fail=1

# Pattern E (25 trials = 20 positive + 5 negative-control)
read -r ke ne <<< "$(count_passes e)"
we="$(wilson_lower_95 "$ke" "$ne")"
printf "  %-9s %12d %12d %19s%% %12s\n" "E (TD)" "$ke" "$ne" "$we" "25/25 → 86.7%"
assert_match "25" "$ke" "Pattern E K=25 (20 pos + 5 neg-control)" || fail=1
assert_match "25" "$ne" "Pattern E N=25" || fail=1
assert_match "86.7" "$we" "Pattern E Wilson 86.7%" || fail=1

# Pattern E negative-control sub-check (the selectivity claim from §27 R10)
e_pos=$(awk -F'\t' 'NR>1 && $2 == "peer_notification" && $3 == "PASS"' "$DATA_DIR/e/trials.tsv" | wc -l)
e_neg=$(awk -F'\t' 'NR>1 && $2 == "issue_routed" && $3 == "PASS"' "$DATA_DIR/e/trials.tsv" | wc -l)
echo ""
echo "## Pattern E selectivity (R10 reinforcement)"
printf "  %-25s %s/%s\n" "peer_notification → skip" "$e_pos" "20"
printf "  %-25s %s/%s\n" "issue_routed → wake"      "$e_neg" "5"
assert_match "20" "$e_pos" "E positive-cell K=20 (peer_notification → skip)" || fail=1
assert_match "5"  "$e_neg" "E negative-control K=5 (issue_routed → wake)"   || fail=1

echo ""
echo "## Cross-check against firing-counts.tsv (already-frozen aggregate)"
fcs="$DATA_DIR/firing-counts.tsv"
for letter in a c d e; do
  upper="$(echo "$letter" | tr 'a-z' 'A-Z')"
  fc_row=$(awk -v p="$upper" '$1 == p {print}' "$fcs")
  if [ -n "$fc_row" ]; then
    fc_k=$(echo "$fc_row" | cut -f2)
    fc_n=$(echo "$fc_row" | cut -f3)
    case "$letter" in
      a) expected_k=20; expected_n=20 ;;
      c) expected_k=20; expected_n=20 ;;
      d) expected_k=20; expected_n=20 ;;
      e) expected_k=25; expected_n=25 ;;
    esac
    [ "$fc_k" = "$expected_k" ] && [ "$fc_n" = "$expected_n" ] && \
      printf "  ✓ Pattern %s firing-counts row matches: K=%s N=%s\n" "$upper" "$fc_k" "$fc_n" || \
      { printf "  ✗ Pattern %s firing-counts row mismatch: K=%s N=%s (expected %s/%s)\n" "$upper" "$fc_k" "$fc_n" "$expected_k" "$expected_n"; fail=1; }
  fi
done

echo ""
if [ "$fail" = "0" ]; then
  echo "✓ All §27 failure-injection values verified from frozen trials.tsv data."
  echo ""
  echo "## Paper §4.4 paste-ready table"
  echo ""
  echo "  Pattern  K/N           Rate     Wilson 95% lower"
  echo "  -------  ------------  -------  ----------------"
  echo "  A (RIA)  $ka/$na         100.0%   ${wa}%"
  echo "  B (PFV)  9/10          90.0%    59.6%   ← prefix-only-validation coverage gap"
  echo "  C (HB)   $kc/$nc         100.0%   ${wc_c}%"
  echo "  D (WPC)  $kd/$nd         100.0%   ${wd}%"
  echo "  E (TD)   $ke/$ne         100.0%   ${we}%   (20 positive + 5 negative-control)"
  echo ""
  echo "  Net total: $((ka + 9 + kc + kd + ke))/$((na + 10 + nc + nd + ne)) = $(python3 -c "print(f'{100*($ka + 9 + $kc + $kd + $ke)/($na + 10 + $nc + $nd + $ne):.1f}')")% net firing rate"
  echo ""
  echo "Note: Pattern B data lives on code-agent's paper-injection/b-harness branch"
  echo "      (not yet merged to main). Documented values used; will verify against"
  echo "      frozen trials.tsv once B PR ships."
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

#!/usr/bin/env bash
# analyze §09 Instance 6 cross-agent recursion (R7: §4.4)
#
# Reads frozen instance-6-recursion/turn-ends.tsv (re-extracted 2026-05-09 from
# the two macf-tester session logs at 2026-04-27 08:17 UTC). Verifies §09's
# claim:
#   - 19 alternating turn-end events between tester-1 ↔ tester-2
#   - Span: 47.0s
#   - = 9.5 full cross-agent cycles before manual termination
#   - Pattern E fix shipped in macf v0.2.4 (silent-fallback Instance 6 retired)
#
# Anchors §28 R7 + paper §4.1 Table 1 row 6 (Instance 6 trace).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA="$WORKSPACE/data/instance-6-turn-ends.tsv"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

echo "=== §09 Instance 6 recursion (R7) ==="
echo ""

n=$(awk 'NR>1' "$DATA" | wc -l)
first_ts=$(awk -F'\t' 'NR==2 {print $1}' "$DATA")
last_ts=$(awk -F'\t' 'NR>1' "$DATA" | tail -1 | cut -f1)
span_s=$(python3 -c "
from datetime import datetime
a = datetime.fromisoformat('$first_ts'.replace('Z', '+00:00'))
b = datetime.fromisoformat('$last_ts'.replace('Z', '+00:00'))
print(f'{(b-a).total_seconds():.1f}')
")
cycles=$(python3 -c "print(f'{$n / 2:.1f}')")

# Verify alternating tester pattern (§09 prose)
alternating_check=$(python3 -c "
prev_tester = None
alternating = True
with open('$DATA') as f:
    next(f)  # header
    for line in f:
        parts = line.strip().split('\t')
        tester = parts[1]
        if prev_tester and prev_tester == tester:
            alternating = False
            break
        prev_tester = tester
print('YES' if alternating else 'NO')
")

echo "## Recursion turn-ends (frozen TSV; 2026-04-27 08:17:08-08:17:55 UTC)"
printf "  %-30s %s\n" "Total turn-end events:" "$n"
printf "  %-30s %s\n" "First event:"            "$first_ts"
printf "  %-30s %s\n" "Last event:"             "$last_ts"
printf "  %-30s %s seconds\n" "Span:"           "$span_s"
printf "  %-30s %s\n" "Full cross-agent cycles:" "$cycles"
printf "  %-30s %s\n" "Alternating tester-1 ↔ tester-2:" "$alternating_check"

echo ""
echo "## Verification against §09 documented values"
fail=0
assert_match "19" "$n" "19 alternating turn-end events"            || fail=1
assert_match "47.0" "$span_s" "47.0s recursion span"               || fail=1
assert_match "9.5" "$cycles" "9.5 full cross-agent cycles"         || fail=1
assert_match "YES" "$alternating_check" "alternating tester-1 ↔ tester-2 pattern" || fail=1

# Mean cycle latency: 47s / 19 = 2.47s; full cycle = 5.0s (per §09)
mean_event_latency=$(python3 -c "print(f'{$span_s/$n:.2f}')")
mean_cycle_latency=$(python3 -c "print(f'{$span_s/$cycles:.2f}')")
echo ""
printf "  %-30s %s s/event\n" "Mean event latency:"  "$mean_event_latency"
printf "  %-30s %s s/cycle\n" "Mean cycle latency:"  "$mean_cycle_latency"
assert_match "4.95" "$mean_cycle_latency" "5.0 s/cycle (per §09 prose)"  || fail=1

echo ""
if [ "$fail" = "0" ]; then
  echo "✓ §09 Instance 6 cross-agent recursion VERIFIED."
  echo ""
  echo "## Paper §4.1 Table 1 / row 6 anchor"
  echo "  - 19 alternating turn-ends between tester-1 ↔ tester-2"
  echo "  - 47.0s span = 9.5 full cross-agent cycles"
  echo "  - 5.0 s/cycle (LLM processing + MCP push + tmux wake + fresh-turn setup)"
  echo "  - Paper says '8 cycles in 50s' — measurement is 9.5/47.0; paper's"
  echo "    framing is conservative + pessimistic on time, optimistic on cycles"
  echo "  - Pattern E fix (macf v0.2.4 / #267) retired Instance 6 structurally"
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

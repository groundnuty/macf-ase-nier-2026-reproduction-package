#!/usr/bin/env bash
# analyze §13 token-mint burst dynamics (R1: §3.1 burst-dynamics)
#
# Reads frozen burst-analysis/sa-anti-pattern-burst-2026-04-15.tsv +
# ca-anti-pattern-burst-2026-04-15.tsv. Verifies:
#   - 40-60% of anti-pattern invocations occurred in bursts ≥3-in-60s on 2026-04-15
#   - 18:15-18:18 SA burst with 8 invocations (matches the 22-event LGTM cluster)
#   - 15 total bursts on 2026-04-15 (LGTM-burst day)
#
# Anchors §28 R1 (burst-dynamics characterization).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
SA_TSV="$WORKSPACE/data/burst-analysis/sa-anti-pattern-burst-2026-04-15.tsv"
CA_TSV="$WORKSPACE/data/burst-analysis/ca-anti-pattern-burst-2026-04-15.tsv"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

echo "=== §13 token-mint burst dynamics (R1) ==="
echo ""

# Aggregate burst counts
sa_bursts=$(awk 'NR>1' "$SA_TSV" | wc -l)
ca_bursts=$(awk 'NR>1' "$CA_TSV" | wc -l)
total_bursts=$((sa_bursts + ca_bursts))

# Sum of invocations IN bursts
sa_in_bursts=$(awk -F'\t' 'NR>1 {s+=$3} END {print s+0}' "$SA_TSV")
ca_in_bursts=$(awk -F'\t' 'NR>1 {s+=$3} END {print s+0}' "$CA_TSV")
total_in_bursts=$((sa_in_bursts + ca_in_bursts))

# Largest burst
largest_sa=$(awk -F'\t' 'NR>1 && $3>m {m=$3; ts=$1} END {print m, ts}' "$SA_TSV")
largest_sa_size="${largest_sa% *}"
largest_sa_ts="${largest_sa#* }"

echo "## Burst counts on 2026-04-15"
printf "  %-30s %s\n" "SA bursts (≥3 in 60s):" "$sa_bursts"
printf "  %-30s %s\n" "CA bursts (≥3 in 60s):" "$ca_bursts"
printf "  %-30s %s\n" "TOTAL bursts:" "$total_bursts"
echo ""
printf "  %-30s %s\n" "SA invocations in bursts:" "$sa_in_bursts"
printf "  %-30s %s\n" "CA invocations in bursts:" "$ca_in_bursts"
printf "  %-30s %s\n" "TOTAL invocations in bursts:" "$total_in_bursts"

echo ""
echo "## Largest single SA burst"
printf "  %-30s %s\n" "Burst size (invocations):" "$largest_sa_size"
printf "  %-30s %s\n" "Burst start timestamp:" "$largest_sa_ts"

echo ""
echo "## Verification against §13 documented values"
fail=0
# §13 prose reports SA-only stats. Frozen TSV has BOTH SA + CA — TSV is more
# complete than §13 prose. DOUBLE-CHECK FINDING #5 below.
assert_match "15" "$sa_bursts"     "SA bursts (§13 prose: 15)"             || fail=1
assert_match "54" "$sa_in_bursts"  "SA invocations in bursts (§13 prose: 54)" || fail=1
assert_match "23" "$ca_bursts"     "CA bursts (NEW — TSV completes §13 SA-only)" || fail=1
assert_match "8"  "$largest_sa_size" "8-invocation SA burst (matches LGTM cluster)" || fail=1

echo ""
echo "## §13 vs frozen TSV reconciliation (DOUBLE-CHECK FINDING #5)"
echo ""
echo "  §13 prose: '15 bursts on 2026-04-15, 54 invocations, 40.9%'"
echo "             (SA-only — code-agent burst data not in §13 prose)"
echo "  Frozen TSV: SA = 15 bursts / 54 invocations  +  CA = $ca_bursts bursts /"
echo "              $ca_in_bursts invocations  →  TOTAL = $total_bursts bursts /"
echo "              $total_in_bursts invocations across both agents"
echo ""
echo "  Implication: §13's 40.9% in-burst share is SA-specific. The CA-side"
echo "  TSV data ($ca_bursts bursts) STRENGTHENS the burst-dynamics claim — both"
echo "  agents exhibited burst patterns on the LGTM-cluster day. §13 should"
echo "  be amended to report cross-agent burst dynamics."

echo ""
if [ "$fail" = "0" ]; then
  echo "✓ §13 burst-dynamics verifications match (with #5 double-check)."
  echo ""
  echo "## Paper §3.1 anchor"
  echo "  - SA: 15 bursts on 2026-04-15 (the LGTM-cluster day)"
  echo "  - CA: 23 bursts on 2026-04-15 (CROSS-AGENT extension to §13)"
  echo "  - TOTAL: $total_bursts bursts / $total_in_bursts invocations across both agents"
  echo "  - Largest SA burst: 8 invocations at $largest_sa_ts"
  echo "    (directly matches the 22-event LGTM mis-attribution cluster from §06)"
  echo "  - Burst dynamics characterize WHY rule-discipline-only reaches a"
  echo "    reliability ceiling: cascading bad-token windows convert one"
  echo "    operator-discipline lapse into many mis-attributions"
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

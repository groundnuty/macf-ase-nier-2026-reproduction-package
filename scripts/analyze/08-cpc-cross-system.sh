#!/usr/bin/env bash
# analyze §08 CPC cross-system reproduction
#
# Reads frozen cpc-aggregate-summary.txt + cpc-attribution/.
# Verifies:
#   - 14,884 anti-pattern events in CPC corpus across 922 sessions / 41 days
#   - 0 helper-script references (CPC didn't adopt MACF defenses)
#   - 0 hook-fire / attribution-trap markers (CPC ran rule-discipline-only)
#   - Cross-system class-confirmation: CPC = clean control group
#
# Anchors/B-regime (CPC 7.1% rule-discipline ceiling).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUMMARY="$WORKSPACE/data/session-logs/cpc-aggregate-summary.txt"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

echo "=== §08 CPC cross-system reproduction ==="
echo ""

if [ ! -f "$SUMMARY" ]; then
  echo "✗ cpc-aggregate-summary.txt not found at $SUMMARY" >&2
  exit 1
fi

echo "## CPC corpus aggregate (frozen summary)"
sed -n '/Aggregate metrics:/,/Project lifetime:/p' "$SUMMARY" | head -10
echo ""

# Extract documented values
ap_events=$(grep -oE 'Anti-pattern.*[0-9,]+ grep' "$SUMMARY" | grep -oE '[0-9,]+' | tr -d ',')
helper_refs=$(grep -oE 'Token-helper script references:[[:space:]]+[0-9]+' "$SUMMARY" | grep -oE '[0-9]+$')
hook_markers=$(grep -oE 'Hook-fire.*markers:[[:space:]]+[0-9]+' "$SUMMARY" | grep -oE '[0-9]+$')
total_sessions=$(grep -oE 'Total jsonl files:[[:space:]]+[0-9]+' "$SUMMARY" | grep -oE '[0-9]+$')
total_dirs=$(grep -oE 'Total project dirs:[[:space:]]+[0-9]+' "$SUMMARY" | grep -oE '[0-9]+$')

echo "## Verification against §08 documented values"
fail=0
assert_match "14884" "$ap_events"     "14,884 anti-pattern grep hits in CPC"  || fail=1
assert_match "0"     "$helper_refs"   "0 helper-script references (clean control)" || fail=1
assert_match "0"     "$hook_markers"  "0 hook-fire markers (no defense to fire)"  || fail=1
assert_match "922"   "$total_sessions" "922 jsonl files (CPC sessions)"        || fail=1
assert_match "31"    "$total_dirs"    "31 project dirs (1 main + 30 worktrees)" || fail=1

# Cross-system ratio: 14,884 CPC vs 2,248 MACF substrate
echo ""
echo "## Cross-system anti-pattern ratio"
macf_ap=2248  # documented in §08
ratio=$(python3 -c "print(f'{$ap_events/$macf_ap:.1f}')")
echo "  CPC: $ap_events anti-pattern events"
echo "  MACF substrate: $macf_ap anti-pattern events"
echo "  Ratio: $ratio× (CPC fired the pattern $ratio× more than MACF)"
assert_match "6.6" "$ratio" "ratio CPC/MACF anti-pattern (6.6×; §08 prose)" || fail=1

echo ""
if [ "$fail" = "0" ]; then
  echo "✓ §08 CPC cross-system verifications match."
  echo ""
  echo "## Paper §1¶3 + §4.2 anchor (regime-B evidence)"
  echo "  - CPC ran rule-discipline-only (no helper, no hook)"
  echo "  - 14,884 anti-pattern firings across 922 sessions / 41 days"
  echo "  - 0 adoption of MACF defenses → clean control group"
  echo "  - Cross-system class-confirmation of the rule-discipline ceiling"
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

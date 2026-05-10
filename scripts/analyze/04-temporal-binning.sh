#!/usr/bin/env bash
# analyze §04 temporal binning
#
# Reads frozen op-actions.tsv and emits the pre/post-#140 era split that
# anchors paper §4.2's replacement claim:
#   - Pre-2026-04-21 (rule-discipline only, ~7 days): 31 bot-intent op-attributed
#     events → rate 4.4/day
#   - Post-2026-04-21 (structural enforcement, ~18 days): 5 events surfaced by
#     conservative heuristic, all forensically classified as legitimate
#     operator-as-reporter actions per §04 → 0 true mis-attributions
#   - Reduction: 4.4/day → 0/day; 12× reduction in unsafe pattern usage
#     (when paired with §06 session-log evidence)
#
# Reviewer-runnable from a clean clone — needs only bash + awk.
#
# Verifies output against §04's documented numbers. Exits non-zero on mismatch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA="$WORKSPACE/data/op-actions.tsv"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

CUTOFF_DATE="2026-04-21"

# §04's bot-intent classifier — matches the heuristic in script #04.
# Rule: body matches LGTM / @-bot-mention / picking-up / merge-related
# OR the event is a closure (closed-by an op).
# Per §04: "CONSERVATIVE classifier — over-counts mis-attribution
# candidates. Final classification requires per-event manual inspection."
classify_bot_intent() {
  local body_lower; body_lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  local type="$2"
  if [ "$type" = "closure" ]; then
    echo "1"; return
  fi
  if printf '%s' "$body_lower" | grep -qE 'lgtm|@.*-agent\[bot\]|^pr.*ready|^picking up|merged|^closing.*verified|^[a-z]+: |post-pr.*update|fix(|ed|es).*#[0-9]'; then
    echo "1"; return
  fi
  echo "0"
}

echo "=== §04 temporal binning ==="
echo "Reproducing paper §4.2 pre/post-#140 transition."
echo ""
echo "Cutoff: $CUTOFF_DATE (PreToolUse hook + 4 canonical scripts deployed)"
echo "Source: $DATA"
echo ""

# Counts per era
pre_count=0
post_count=0

while IFS='|' read -r date login type url body repo; do
  bot_intent="$(classify_bot_intent "$body" "$type")"
  if [ "$bot_intent" = "1" ]; then
    if [ "$date" \< "$CUTOFF_DATE" ]; then
      pre_count=$((pre_count + 1))
    else
      post_count=$((post_count + 1))
    fi
  fi
done < "$DATA"

# Window sizes per §04: ~7 days pre, ~18 days post
pre_days=7
post_days=18
pre_rate=$(python3 -c "print(f'{$pre_count/$pre_days:.2f}')")
post_rate=$(python3 -c "print(f'{$post_count/$post_days:.2f}')")

echo "## Pre/post-#140 split"
printf "  %-50s %10s %10s\n" "era" "events" "rate/day"
printf "  %-50s %10d %10s\n" "Pre-#140 (rule-discipline only, ~7 days)"  "$pre_count" "$pre_rate"
printf "  %-50s %10d %10s\n" "Post-#140 (structural enforcement, ~18 days)" "$post_count" "$post_rate"

echo ""
echo "## Verification against §04 documented values"
fail=0
assert_match "31" "$pre_count"  "pre-#140 bot-intent events"   || fail=1
assert_match "5"  "$post_count" "post-#140 bot-intent events (heuristic; per §04 all 5 forensically classified as legitimate)" || fail=1
assert_match "4.43" "$pre_rate"  "pre-#140 rate (4.4/day)"     || fail=1
assert_match "0.28" "$post_rate" "post-#140 rate (0.28/day)"   || fail=1

echo ""
if [ "$fail" = "0" ]; then
  echo "✓ All §04 documented values verified from frozen data."
  echo ""
  echo "## Paper §4.2 anchors"
  echo "  - 31 events pre-#140 → 0 true mis-attributions post-#140"
  echo "    (5 post-#140 events surfaced by heuristic; all forensically"
  echo "     classified as legitimate operator-as-reporter actions per §04)"
  echo "  - Rate: 4.4/day → 0/day"
  echo "  - 7-day pre-defense + 18-day post-defense window"
  echo ""
  echo "Note: §06 session-log evidence shows the underlying anti-pattern Bash usage"
  echo "fell from 45.4% → 3.7% (12× reduction) over the same era — see analyze-06."
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

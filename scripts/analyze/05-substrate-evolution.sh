#!/usr/bin/env bash
# analyze §05 substrate evolution timeline
#
# Reads frozen substrate-evolution/timeline.tsv (re-extracted 2026-05-09 via
# §05 git-log walk over 5 macf-* repos). Verifies §04's documented inflection
# points:
#   - 2026-04-13: testing.md / types.md (earliest substrate rules; macf workbench)
#   - 2026-04-14: workbench creation (agent-identity.md + 4 other rules)
#   - 2026-04-17: helper scripts deployed in code-agent workbench
#   - 2026-04-21: STRUCTURAL ENFORCEMENT LANDED — check-gh-token.sh + macf-gh-token.sh
#                  + tmux-send-to-claude.sh + macf-whoami.sh + coordination.md canonical
#                  All landed atomically across science-agent + code-agent workbenches
#
# Anchors §04 § "Substrate workbench evolution" timeline + §28 R3.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMELINE="$WORKSPACE/data/substrate-timeline.tsv"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

echo "=== §05 substrate evolution timeline ==="
echo ""

if [ ! -f "$TIMELINE" ]; then
  echo "✗ timeline.tsv not found at $TIMELINE" >&2
  exit 1
fi

n_total=$(awk 'NR>1' "$TIMELINE" | wc -l)
n_pre=$(awk -F'\t' 'NR>1 && $1<"2026-04-21"' "$TIMELINE" | wc -l)
n_post=$(awk -F'\t' 'NR>1 && $1>="2026-04-21"' "$TIMELINE" | wc -l)
n_defense_day=$(awk -F'\t' 'NR>1 && $1=="2026-04-21"' "$TIMELINE" | wc -l)

echo "## Substrate workbench timeline (frozen 2026-05-09)"
printf "  %-40s %d\n" "Total artifacts (rules + scripts):" "$n_total"
printf "  %-40s %d\n" "Pre-#140 (before 2026-04-21):" "$n_pre"
printf "  %-40s %d\n" "Post-#140 (2026-04-21 onward):" "$n_post"
printf "  %-40s %d\n" "On 2026-04-21 (defense-landing day):" "$n_defense_day"

echo ""
echo "## Key inflection points"

# 2026-04-13: earliest substrate rules in macf workbench
earliest_date=$(awk -F'\t' 'NR>1 {print $1}' "$TIMELINE" | sort | head -1)
echo "  Earliest artifact: $earliest_date"

# 2026-04-21: structural enforcement day
echo ""
echo "  2026-04-21 (structural enforcement landing):"
awk -F'\t' '$1 == "2026-04-21" {print "    " $2 "  →  " $3}' "$TIMELINE"

echo ""
echo "## Verification against §04 documented inflection points"
fail=0
assert_match "2026-04-13" "$earliest_date" "earliest substrate rule date" || fail=1

# Verify 4 UNIQUE structural-defense scripts landed on 2026-04-21 (per §04 prose)
# (raw row count is 5 because check-gh-token.sh is in both workbenches; we want unique)
unique_defense_scripts=$(awk -F'\t' '$1 == "2026-04-21" && $2 ~ /^script:/ {print $2}' "$TIMELINE" | sort -u | wc -l)
assert_match "4" "$unique_defense_scripts" "4 unique structural-defense scripts on 2026-04-21" || fail=1

# Verify check-gh-token.sh deployed atomically in BOTH workbenches on 04-21
chgt_count=$(awk -F'\t' '$1 == "2026-04-21" && $2 == "script:check-gh-token.sh"' "$TIMELINE" | wc -l)
assert_match "2" "$chgt_count" "check-gh-token.sh in 2 workbenches on 2026-04-21 (atomic)" || fail=1

# Verify coordination.md (canonical rule) landed on 2026-04-21
coord_check=$(awk -F'\t' '$1 == "2026-04-21" && $2 == "rule:coordination.md"' "$TIMELINE" | wc -l)
[ "$coord_check" -ge "1" ] && echo "  ✓ coordination.md canonical rule landed on 2026-04-21" || { echo "  ✗ coordination.md not found on 2026-04-21" >&2; fail=1; }

echo ""
if [ "$fail" = "0" ]; then
  echo "✓ §05 substrate-evolution timeline VERIFIED."
  echo ""
  echo "## Paper §3.3 + §4.5 anchor"
  echo "  - Substrate workbenches created 2026-04-13/14"
  echo "  - Crisis day 2026-04-17 (5+ trap firings; macf#140 filed shortly after)"
  echo "  - **Structural enforcement landed atomically 2026-04-21**:"
  echo "      check-gh-token.sh (PreToolUse hook) + 3 helper scripts +"
  echo "      coordination.md canonical rule, deployed across both substrate"
  echo "      workbenches the same day"
  echo "  - Post-#140 era begins 2026-04-21; 4-mechanism stack operational"
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

#!/usr/bin/env bash
# analyze §15 CPC adoption of MACF helpers
#
# Reads frozen cpc-aggregate-summary.txt and verifies:
#   - 0 references to macf-gh-token across 922 CPC session log files
#   - 0 references to MACF_SKIP_TOKEN_CHECK or PreToolUse hook
#   - CPC stayed rule-discipline-only by inaction → clean control group
#
# Anchors "CPC = clean control group" framing (no MACF defense diffusion).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUMMARY="$WORKSPACE/data/session-logs/cpc-aggregate-summary.txt"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

echo "=== §15 CPC adoption of MACF helpers ==="
echo ""

# Extract documented absence values
helper_refs=$(grep -oE 'Token-helper script references:[[:space:]]+[0-9]+' "$SUMMARY" | grep -oE '[0-9]+$')
hook_markers=$(grep -oE 'Hook-fire.*markers:[[:space:]]+[0-9]+' "$SUMMARY" | grep -oE '[0-9]+$')
sessions=$(grep -oE 'Total jsonl files:[[:space:]]+[0-9]+' "$SUMMARY" | grep -oE '[0-9]+$')

echo "## CPC corpus — absence-of-MACF-defenses verification"
printf "  %-45s %d\n" "Total CPC sessions scanned:" "$sessions"
printf "  %-45s %d\n" "macf-gh-token script references:"   "$helper_refs"
printf "  %-45s %d\n" "Hook-fire / attribution-trap markers:" "$hook_markers"

echo ""
echo "## Verification against §15 documented values"
fail=0
assert_match "0"   "$helper_refs"  "0 macf-gh-token references in CPC (no diffusion)" || fail=1
assert_match "0"   "$hook_markers" "0 hook-fire markers in CPC (no defense)"          || fail=1
assert_match "922" "$sessions"     "922 CPC session log files scanned"                || fail=1

echo ""
if [ "$fail" = "0" ]; then
  echo "✓ §15 CPC-clean-control-group VERIFIED."
  echo ""
  echo "## Paper §1¶3 anchor"
  echo "  - CPC sessions extend to 2026-05-05 (overlaps the MACF #140 era)"
  echo "  - 0 of 922 CPC sessions reference MACF's helper script"
  echo "  - CPC = clean control group: no defense diffusion despite proximity"
  echo "  - Reinforces regime-B claim that CPC's 7.1% mis-attribution rate"
  echo "    was rule-discipline-only (not contaminated by MACF defenses)"
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

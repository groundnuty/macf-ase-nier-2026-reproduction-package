#!/usr/bin/env bash
# analyze §20 consumer-fleet attribution (R4: §3.3 reinforcement)
#
# Reads frozen hook-fires-real.jsonl (substrate over-inclusive scan).
# Verifies:
#   - 13 over-inclusive substrate matches in the bundle
#   - Per §07 filter (must be tool_use + Bash + actual hook output): 0 real
#     autonomous hook fires in substrate
#   - §20's "8 real autonomous hook fires" claim is for CONSUMER fleet (PPAM
#     workspaces on operator's macbook) — NOT in this bundle
#
# **DOUBLE-CHECK FINDING #6**: The 8-fires-on-consumer-fleet claim depends on
# SSH-derived data that's not in the public replication package. For full
# §20 reproducibility, redacted PPAM session-log slices would need to be
# shipped (see §29 P1 option). This is a structural limitation, not an error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_FIRES="$WORKSPACE/data/session-logs/hook-fires-real.jsonl"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

echo "=== §20 consumer-fleet attribution (R4) ==="
echo ""

# Aggregate the substrate over-inclusive scan
total_entries=$(wc -l < "$HOOK_FIRES")
sa_substrate=$(jq -r 'select(.src == "macf-science-agent") | .src' "$HOOK_FIRES" 2>/dev/null | wc -l)
ca_substrate=$(jq -r 'select(.src == "macf") | .src' "$HOOK_FIRES" 2>/dev/null | wc -l)

echo "## Substrate hook-fires scan (frozen JSONL — over-inclusive)"
printf "  %-40s %d\n" "Total entries:" "$total_entries"
printf "  %-40s %d\n" "Science-agent substrate:" "$sa_substrate"
printf "  %-40s %d\n" "Code-agent (macf) substrate:" "$ca_substrate"

echo ""
echo "## Filter to real autonomous hook fires (§07 methodology)"
echo "  Per §07: 'real' = tool_use + name=Bash + command containing hook STDERR"
echo "  Per §07 + §20 Substrate row: 0 real autonomous hook fires across 19 days"
echo "  The over-inclusive 13 entries are tool_results that mentioned hook script"
echo "  content (e.g., agent reading the hook source file) — not actual blocks."
echo ""
echo "## §20 consumer-fleet claim (NOT in bundle — SSH-derived from operator macbook)"
echo "  §20 documents 8 real autonomous hook fires across 14 days on 2 PPAM workspaces:"
echo "    - 3 fires from ppam-2026 on 2026-05-07"
echo "    - 5 fires from cyfronet-llm-forge on 2026-05-01"
echo "  These are the consumer-fleet evidence — extracted via SSH to operator's"
echo "  macbook; redacted PPAM session-log slices NOT included in the public bundle."

echo ""
echo "## Verification against §20 + §07 documented values"
fail=0
assert_match "13" "$total_entries" "13 over-inclusive substrate entries in JSONL" || fail=1
# Note: substrate REAL fires per §07 = 0 (after filter); we don't re-implement
# the full §07 filter here, just verify the over-inclusive scan exists.

echo ""
echo "## DOUBLE-CHECK FINDING #6 — bundle limitation"
echo ""
echo "  §20's '8 real autonomous hook fires on PPAM consumer fleet' is the"
echo "  §28 R4 reinforcement claim. The PPAM session JSONLs are private (on"
echo "  operator's macbook) and NOT in the public replication package."
echo ""
echo "  For full §20 reproducibility (§29 option P1):"
echo "    - Ship redacted PPAM session-log slices (operator name + paths"
echo "      scrubbed; ~few MB total)"
echo "    - Add analyze script that scans the redacted slices for"
echo "      'BLOCKED by MACF attribution-trap hook' markers"
echo ""
echo "  Until P1 is done, the §20 8-fires claim is verified ONLY via §20's"
echo "  prose + the documented SSH methodology. This is a known bundle"
echo "  limitation, not an error."

if [ "$fail" = "0" ]; then
  echo ""
  echo "✓ §20 substrate-side over-inclusive scan VERIFIED (with #6 limitation)."
  echo ""
  echo "## Paper §3.3 anchor"
  echo "  - Substrate: 0 real autonomous hook fires across 19 days post-#140"
  echo "    (§07 filter applied to over-inclusive 13-entry scan)"
  echo "  - Consumer fleet (PPAM, ~14 days): 8 real autonomous hook fires"
  echo "    [SSH-derived; not in public bundle — limitation per §29 P1]"
  echo "  - Defense actively works at consumer scale (vs substrate where"
  echo "    agents internalized the new pattern after #140 design)"
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

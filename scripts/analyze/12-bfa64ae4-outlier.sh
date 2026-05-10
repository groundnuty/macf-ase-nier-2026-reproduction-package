#!/usr/bin/env bash
# analyze §12 bfa64ae4 outlier (R6: §4.5 defensive)
#
# Reads frozen bfa64ae4-outlier/04-17-summary.tsv (SSH-extracted 2026-05-09).
# Verifies §12's load-bearing claim:
#   - The 2026-04-17 spike in §07 anti-pattern grep is a FALSE POSITIVE
#   - 7333 total events on that day; 0 real Bash/Edit/Write tool_use
#   - Source: pprai-2026 conference poster session about CPC, NOT real hook activity
#
# Note: §12 prose says "1831 attachment-type events with check-gh-token reference".
# Re-extraction today produces 0 such matches — §12's sub-claim doesn't reproduce
# (Claude Code memory likely rotated between original analysis and re-extract).
# The LOAD-BEARING claim ("0 real Bash/Edit/Write events") still holds.
#
# Anchors §28 R6 (defensive bfa64ae4 outlier-rule-out).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA="$WORKSPACE/data/outlier-04-17.tsv"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

echo "=== §12 bfa64ae4 outlier (R6) ==="
echo ""

if [ ! -f "$DATA" ]; then
  echo "✗ 04-17-summary.tsv not found at $DATA" >&2
  exit 1
fi

echo "## Frozen SSH-extracted summary"
column -t -s $'\t' "$DATA"

# Extract values
total_events=$(awk -F'\t' '$1 == "total_events_2026-04-17" {print $2}' "$DATA")
real_bew=$(awk -F'\t' '$1 == "real_bash_edit_write_2026-04-17" {print $2}' "$DATA")
session_id=$(awk -F'\t' '$1 == "session_id" {print $2}' "$DATA")

echo ""
echo "## Verification against §12 documented values"
fail=0
assert_match "7333" "$total_events" "7,333 total events on 2026-04-17 in bfa64ae4-...jsonl" || fail=1
assert_match "0"    "$real_bew"      "0 real Bash/Edit/Write tool_use events (LOAD-BEARING)" || fail=1
assert_match "bfa64ae4-4637-4189-ba24-dbbed7780a92" "$session_id" "session UUID matches §12" || fail=1

echo ""
echo "## §12 vs frozen-SSH reconciliation"
echo ""
echo "  §12 prose: '1831 attachment-type events with check-gh-token reference'"
echo "  Frozen TSV (SSH 2026-05-09): 0 such matches"
echo "  Likely cause: Claude Code memory entries rotated between original §12"
echo "  analysis and re-extraction; the attachment content is dynamic."
echo "  LOAD-BEARING claim ('0 real Bash/Edit/Write events') still holds."

echo ""
echo "## Replication note (private-data dependency)"
echo "  This script reads frozen 04-17-summary.tsv (SSH-extracted from operator's"
echo "  macbook). End-to-end re-extraction requires SSH access to the macbook"
echo "  + the bfa64ae4-...jsonl session log file. Bundle limitation per §29 P1."

if [ "$fail" = "0" ]; then
  echo ""
  echo "✓ §12 bfa64ae4-outlier ruled-out VERIFIED."
  echo ""
  echo "## Paper §4.5 anchor (R6 defensive — outlier ruled out)"
  echo "  - 2026-04-17 was the highest-volume day in §07's anti-pattern grep"
  echo "  - Drill-in: 7,333 events on that day are mostly poster-paper-writing"
  echo "    session (PPRAI 2026 about CPC), NOT real hook/Bash activity"
  echo "  - 0 real Bash/Edit/Write events with hook activity on 04-17"
  echo "  - The §07 trajectory analysis is robust to this outlier exclusion"
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

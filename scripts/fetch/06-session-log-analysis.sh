#!/usr/bin/env bash
# Session-log analysis: agent-side observation of Instance 1 trap firings.
# Counts anti-pattern (`gh token generate | jq`) vs canonical helper
# (`macf-gh-token.sh`) usage by date across substrate session logs.
#
# Usage:
#   ./06-session-log-analysis.sh [output_dir]
#
# Output:
#   anti-pattern-vs-helper-daily.tsv   — per-day counts
#   hook-fires-real.jsonl              — candidate hook-fire events
#   era-summary.txt                    — pre-#140 vs post-#140 aggregate

set -euo pipefail

OUT=${1:-/tmp/claude/session-log-analysis}
mkdir -p "$OUT"

LOG_DIR=~/.claude/projects
SUBSTRATE_LOGS=(
  "$LOG_DIR/-HOME-repos-groundnuty-macf-science-agent"
  "$LOG_DIR/-HOME-repos-groundnuty-macf"
  "$LOG_DIR/-HOME-repos-groundnuty-macf-devops-toolkit"
)
CUTOFF="2026-04-21"  # Date when PreToolUse hook + 4 canonical scripts deployed via macf rules refresh

echo "[1/3] Counting anti-pattern + helper usage by date..." >&2
{
  for dir in "${SUBSTRATE_LOGS[@]}"; do
    [ -d "$dir" ] || continue
    for log in "$dir"/*.jsonl; do
      [ -f "$log" ] || continue
      grep "gh token generate.*jq" "$log" 2>/dev/null \
        | jq -r '.timestamp[:10] // empty | "ANTI\t\(.)"' 2>/dev/null
      grep "macf-gh-token.sh" "$log" 2>/dev/null \
        | jq -r '.timestamp[:10] // empty | "HELPER\t\(.)"' 2>/dev/null
    done
  done
} | sort | uniq -c | awk -v cutoff="$CUTOFF" '
BEGIN {OFS="\t"; print "date", "anti_pattern", "helper", "era"}
{key = $3; if ($2 == "ANTI") ap[key] = $1; else helper[key] = $1}
END {
  for (d in ap) dates[d] = 1
  for (d in helper) dates[d] = 1
  n = asorti(dates, sd)
  for (i = 1; i <= n; i++) {
    d = sd[i]
    era = (d < cutoff) ? "pre-140" : "post-140"
    printf "%s\t%d\t%d\t%s\n", d, ap[d]+0, helper[d]+0, era
  }
}' > "$OUT/anti-pattern-vs-helper-daily.tsv"

echo "[2/3] Computing era summary..." >&2
awk -F'\t' '
NR == 1 {next}
{ap[$4] += $2; h[$4] += $3}
END {
  print "Era summary"
  print "==========="
  for (e in ap) {
    total = ap[e] + h[e]
    pct = total > 0 ? 100 * ap[e] / total : 0
    printf "%-10s  anti=%-5d  helper=%-5d  total=%-5d  anti-share=%.2f%%\n", e, ap[e], h[e], total, pct
  }
}' "$OUT/anti-pattern-vs-helper-daily.tsv" > "$OUT/era-summary.txt"

echo "[3/3] Capturing real hook-fire events..." >&2
: > "$OUT/hook-fires-real.jsonl"
for dir in "${SUBSTRATE_LOGS[@]}"; do
  [ -d "$dir" ] || continue
  for log in "$dir"/*.jsonl; do
    [ -f "$log" ] || continue
    src=$(basename "$dir" | sed 's/.*-groundnuty-//')
    jq -c --arg src "$src" '
      select(.message?.content?
        | tostring
        | (contains("BLOCKED by MACF attribution-trap hook") and
           (contains("+++ b/scripts/check-gh-token") | not) and
           (contains("+# Override") | not) and
           (contains("+BLOCKED") | not) and
           (contains("--- /dev/null") | not) and
           (contains("Hook behavior sanity") | not)
          )
      ) | {ts: .timestamp, src: $src,
           tool_use_id: (.message?.content?[0]?.tool_use_id // null),
           content_first_1500: ((.message?.content // []) | tostring | .[0:1500])}' "$log" 2>/dev/null
  done
done >> "$OUT/hook-fires-real.jsonl"

echo "" >&2
echo "Outputs in: $OUT/" >&2
echo "" >&2
cat "$OUT/era-summary.txt"
echo ""
echo "Daily breakdown:"
column -t -s $'\t' "$OUT/anti-pattern-vs-helper-daily.tsv"
echo ""
echo "Real hook-fire candidates: $(wc -l < "$OUT/hook-fires-real.jsonl") (most are dev-time tests; see findings doc for filtering)"

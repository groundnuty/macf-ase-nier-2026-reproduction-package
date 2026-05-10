#!/usr/bin/env bash
# §17 — per-failure-mode classification of substrate session log events
#
# For Modes 1-5 of the gh-token-attribution-traps canonical rule, count
# how often each error-signature surfaces in tool_result content of the
# science-agent + code-agent substrate session logs. Mode 3/4 (HTTP 401
# Bad credentials) dominates ~81.9% of observable failures.
#
# Mode 6 (cross-repo cd) is harder to extract from tool_results — it's
# a behavioral pattern, not an error message. Skipped here; covered
# separately by macf#161 closure-doc.
#
# Usage:
#   ./17-per-failure-mode.sh
#
# Output:
#   data/session-logs/per-failure-mode.tsv  -- counts per mode
#   stdout                                                  -- summary

set -euo pipefail

WORKSPACE=<HOME>/repos/groundnuty/macf-science-agent
OUT="$WORKSPACE/data/session-logs/per-failure-mode.tsv"
mkdir -p "$(dirname "$OUT")"

LOG_SA=<HOME>/.claude/projects/-HOME-repos-groundnuty-macf-science-agent/04246354-908e-45e4-8da1-aa687b181178.jsonl
LOG_CA=<HOME>/.claude/projects/-HOME-repos-groundnuty-macf/2e701823-edf6-4e9f-8c37-c7eee5197a44.jsonl

count_mode() {
  local log="$1" pattern="$2"
  jq -c 'select(.message?.content?[0]?.type == "tool_result")' "$log" 2>/dev/null \
    | jq -r '.message.content[0].content // ""' 2>/dev/null \
    | grep -cE "$pattern" 2>/dev/null || echo 0
}

{
  echo -e "mode\tdescription\tsa_count\tca_count\ttotal"
  for entry in \
    "1|key.*fingerprint|invalid.*signature|signature verification" \
    "2|JWT could not be decoded" \
    "3+4|HTTP 401|Bad credentials" \
    "5|macf-gh-token.*No such file|macf-gh-token.*not found"; do
    mode="${entry%%|*}"; rest="${entry#*|}"
    desc="${rest}"
    sa=$(count_mode "$LOG_SA" "$rest")
    ca=$(count_mode "$LOG_CA" "$rest")
    total=$((sa + ca))
    printf "%s\t%s\t%d\t%d\t%d\n" "$mode" "$desc" "$sa" "$ca" "$total"
  done
} > "$OUT"

echo "=== Per-failure-mode classification ==="
column -t -s $'\t' "$OUT"
echo ""
echo "Mode 3+4 (HTTP 401 / Bad credentials) dominates the observable failure surface."
echo "Mode 6 (cross-repo cd) is behavioral, not error-message-based — skipped here;"
echo "see macf#161 closure-doc for mode-6 incident chain."

#!/usr/bin/env bash
# CPC cross-system reproduction analysis. Runs on macbook via SSH.
# Counts anti-pattern + helper + hook events across CPC's session logs,
# aggregates by date, compares to MACF substrate.
#
# Usage:
#   ./08-cpc-cross-system-analysis.sh [ssh-target]
#
# Default ssh-target: <OPERATOR>@<TAILSCALE_IP> (operator's macbook via Tailscale).
#
# Note: requires that the operator's gh stored auth on macbook has read
# access to groundnuty/claude-plan-composer (private repo). For session
# logs alone (no gh API), no auth needed.
#
# CPC corpus: ~/.claude/projects/*claude-plan-composer*/ (31 dirs / 922 jsonl / 1.6 GB)

set -euo pipefail

SSH_TARGET=${1:-<OPERATOR>@<TAILSCALE_IP>}

echo "Running CPC analysis on macbook ($SSH_TARGET)..." >&2

ssh "$SSH_TARGET" 'bash -s' <<'OUTER_EOF'
echo "--- CPC corpus inventory ---"
find ~/.claude/projects -maxdepth 1 -type d -name "*claude-plan-composer*" | wc -l | xargs echo "  CPC project dirs:"
files=$(find ~/.claude/projects -path "*claude-plan-composer*" -name "*.jsonl" -type f 2>/dev/null)
echo "$files" | grep -c . | xargs echo "  jsonl files total:"
echo "$files" | xargs ls -la 2>/dev/null | awk "{s+=\$5} END {printf \"  total bytes: %d MB\\n\", s/1024/1024}"

echo ""
echo "--- Aggregate metrics ---"
total_anti=0; total_helper=0; total_blocked=0
while IFS= read -r log; do
  [ -f "$log" ] || continue
  a=$(grep -c "gh token generate.*jq" "$log" 2>/dev/null)
  h=$(grep -c -E "macf-gh-token\.sh|cpc-gh-token\.sh" "$log" 2>/dev/null)
  b=$(grep -c "BLOCKED by MACF\|BLOCKED by CPC\|attribution-trap hook" "$log" 2>/dev/null)
  a=${a:-0}; h=${h:-0}; b=${b:-0}
  total_anti=$((total_anti + a))
  total_helper=$((total_helper + h))
  total_blocked=$((total_blocked + b))
done <<< "$files"
echo "  Anti-pattern (gh token generate | jq): $total_anti"
echo "  Token-helper script references:        $total_helper"
echo "  Hook-fire / attribution-trap markers:  $total_blocked"

echo ""
echo "--- Per-day anti-pattern usage ---"
echo "$files" | while IFS= read -r log; do
  [ -f "$log" ] && grep "gh token generate.*jq" "$log" 2>/dev/null | jq -r ".timestamp[:10] // empty" 2>/dev/null
done | sort | uniq -c | sort -k2

echo ""
echo "--- Date range ---"
echo "$files" | while IFS= read -r log; do
  [ -f "$log" ] && jq -r 'select(.timestamp != null) | .timestamp[:10]' "$log" 2>/dev/null
done | sort -u > /tmp/cpc-dates.txt
echo "  range: $(head -1 /tmp/cpc-dates.txt) to $(tail -1 /tmp/cpc-dates.txt)"
echo "  active days: $(wc -l < /tmp/cpc-dates.txt)"
OUTER_EOF

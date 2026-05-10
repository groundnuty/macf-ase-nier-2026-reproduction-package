#!/usr/bin/env bash
# Find the literal 8-cycle (actually ~9.5-cycle) cross-agent recursion
# documented in silent-fallback-hazards.md Instance 6, paper §4.1 Table 1.
#
# Usage:
#   ./09-instance-6-recursion-finder.sh
#
# Output:
#   - Per-tester turn-end timestamps in the recursion window
#   - Cycle latency analysis
#   - Post-fix Pattern E events from channel.log (tmux_wake_skipped)
#
# The recursion was on macf-testbed v0.2.3, between macf-tester-1-agent
# and macf-tester-2-agent, at 2026-04-27 08:17 UTC. Pattern E fix shipped
# in macf v0.2.4 / macf#267 — observable in channel.log post-08:43 UTC
# as `tmux_wake_skipped` events with reason `peer_notification_observational`.

set -euo pipefail

LOG_DIR=~/.claude/projects
TESTER1_LOG=$(ls "$LOG_DIR"/-home-ubuntu-tester-1-home/62493c61-f3b*.jsonl 2>/dev/null | head -1)
TESTER2_LOG=$(ls "$LOG_DIR"/-home-ubuntu-tester-2-home/38b5e8fc-6e0*.jsonl 2>/dev/null | head -1)

if [ -z "$TESTER1_LOG" ] || [ -z "$TESTER2_LOG" ]; then
  echo "ERROR: tester session logs not found in $LOG_DIR" >&2
  echo "Expected: -home-ubuntu-tester-{1,2}-home/62493c61-...jsonl + 38b5e8fc-...jsonl" >&2
  exit 1
fi

echo "=== Tester session logs ==="
echo "  tester-1: $TESTER1_LOG"
echo "  tester-2: $TESTER2_LOG"
echo ""

echo "=== Recursion window: 2026-04-27 08:17:00 → 08:18:00 UTC ==="
echo ""

# Extract assistant turn-ends in the window from both tester logs, sorted by time
{
  jq -c 'select(.timestamp >= "2026-04-27T08:17:00" and .timestamp <= "2026-04-27T08:18:00" and .message?.role == "assistant" and (.message?.content?[0]?.type == "text")) | {ts: .timestamp, agent: "tester-1"}' "$TESTER1_LOG" 2>/dev/null
  jq -c 'select(.timestamp >= "2026-04-27T08:17:00" and .timestamp <= "2026-04-27T08:18:00" and .message?.role == "assistant" and (.message?.content?[0]?.type == "text")) | {ts: .timestamp, agent: "tester-2"}' "$TESTER2_LOG" 2>/dev/null
} | jq -s 'sort_by(.ts)' | jq -r '.[] | "\(.ts[11:23]) | \(.agent) | turn-end"'

echo ""
echo "=== Cycle latency: time between consecutive same-tester turn-ends ==="
echo ""

jq -c 'select(.timestamp >= "2026-04-27T08:17:00" and .timestamp <= "2026-04-27T08:18:00" and .message?.role == "assistant" and (.message?.content?[0]?.type == "text")) | .timestamp' "$TESTER1_LOG" 2>/dev/null \
  | sort | awk '
BEGIN {prev = ""}
{
  ts = $0; gsub(/"/, "", ts)
  cmd = "date -d \"" ts "\" +%s.%N 2>/dev/null"
  cmd | getline epoch
  close(cmd)
  if (prev != "") {
    dt = epoch - prev_epoch
    printf "  tester-1 cycle: %s → %s = %.2f s\n", prev, ts, dt
  }
  prev = ts
  prev_epoch = epoch
}'

echo ""
echo "=== Pattern E fix verification (channel.log) ==="
echo ""

for tester in 1 2; do
  log=<HOME>/tester-${tester}-home/.macf/logs/channel.log
  if [ -f "$log" ]; then
    skip_count=$(grep -c "tmux_wake_skipped" "$log" 2>/dev/null)
    skip_count=${skip_count:-0}
    notify_count=$(grep -c "notify_received" "$log" 2>/dev/null)
    notify_count=${notify_count:-0}
    echo "  tester-$tester channel.log:"
    echo "    notify_received events: $notify_count"
    echo "    tmux_wake_skipped events: $skip_count"
    if [ "$notify_count" -gt 0 ]; then
      pct=$(awk "BEGIN{printf \"%.0f\", $skip_count/$notify_count*100}")
      echo "    skip rate: $pct%"
    fi
  fi
done

echo ""
echo "=== Sample Pattern E event from channel.log (post-#267 fix) ==="
log=<HOME>/tester-1-home/.macf/logs/channel.log
if [ -f "$log" ]; then
  grep "tmux_wake_skipped" "$log" 2>/dev/null | head -1 | jq '.'
fi

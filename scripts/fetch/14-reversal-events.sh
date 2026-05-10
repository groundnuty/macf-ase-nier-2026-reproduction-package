#!/usr/bin/env bash
# §14 — reversal events check (post-#140 substrate)
#
# Question: did the post-#140 (2026-04-21+) era have any TRUE regressions
# of the gh-token-attribution anti-pattern in substrate session logs?
# Result: 0 true regressions in 19 days; all matches in session logs are
# either tool_use STRING containing the tokens (in description prose),
# or non-Bash events.
#
# Searches both science-agent and code-agent substrate session logs on
# the VM (no SSH needed; substrate is VM-resident).
#
# Usage:
#   ./14-reversal-events.sh
#
# Output:
#   /tmp/post-140-reversal-check/post-140-real-bash.jsonl  -- raw matches
#   stdout                                                  -- dedup'd summary

set -euo pipefail

TMP=/tmp/post-140-reversal-check
mkdir -p "$TMP"
: > "$TMP/post-140-real-bash.jsonl"

for log in ~/.claude/projects/-HOME-repos-groundnuty-macf*/*.jsonl; do
  src=$(basename "$(dirname "$log")" | sed 's/.*-groundnuty-//')
  jq -c --arg src "$src" '
    select(
      .timestamp >= "2026-04-21" and
      .message?.content?[0]?.type == "tool_use" and
      .message?.content?[0]?.name == "Bash" and
      ((.message?.content?[0]?.input?.command // "") | contains("gh token generate") and contains("jq"))
    ) | {ts: .timestamp, src: $src, cmd: .message.content[0].input.command[0:300]}
  ' "$log" 2>/dev/null
done > "$TMP/post-140-real-bash.jsonl" || true

echo "=== Post-#140 reversal check ==="
echo "Raw matches: $(wc -l < "$TMP/post-140-real-bash.jsonl")"
echo "Dedup'd by timestamp: $(jq -s 'unique_by(.ts) | length' "$TMP/post-140-real-bash.jsonl")"
echo ""
echo "=== Each match — manually classify (the per-event TRUE-vs-FALSE check) ==="
jq -s 'unique_by(.ts) | .[]' "$TMP/post-140-real-bash.jsonl"

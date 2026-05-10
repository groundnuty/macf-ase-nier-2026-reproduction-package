#!/usr/bin/env bash
# Detect bursts in real Bash anti-pattern invocations.
# A "burst" = ≥3 invocations within 60 seconds.
#
# Usage:
#   ./13-token-mint-burst-analysis.sh [date] [output_dir]
#
# Default date: 2026-04-15 (the LGTM-cluster day)
#
# Output:
#   sa-anti-pattern-burst-<date>.tsv
#   ca-anti-pattern-burst-<date>.tsv

set -euo pipefail

DATE=${1:-2026-04-15}
OUT=${2:-/tmp/claude/burst-analysis}
mkdir -p "$OUT"

LOG_SA=~/.claude/projects/-HOME-repos-groundnuty-macf-science-agent/04246354-908e-45e4-8da1-aa687b181178.jsonl
LOG_CA=~/.claude/projects/-HOME-repos-groundnuty-macf/2e701823-edf6-4e9f-8c37-c7eee5197a44.jsonl

extract_real_bash() {
  local log="$1" date="$2"
  jq -c "select(.timestamp[:10] == \"$date\" and .message?.content?[0]?.type == \"tool_use\" and .message?.content?[0]?.name == \"Bash\" and (.message?.content?[0]?.input?.command // \"\" | contains(\"gh token generate\") and contains(\"jq\")))" "$log" 2>/dev/null \
    | jq -r '.timestamp' | sort
}

detect_bursts() {
  local label="$1" timestamps_file="$2" output_tsv="$3"
  echo -e "burst_start\tburst_end\tinvocations\tagent" > "$output_tsv"
  awk -v src="$label" '
  {
    cmd = "date -d \"" $0 "\" +%s"; cmd | getline epoch; close(cmd)
    if (last_epoch > 0 && epoch - last_epoch <= 60) {
      if (in_burst == 0) { burst_start = last_ts; burst_count = 2; in_burst = 1 }
      else burst_count++
    } else {
      if (in_burst == 1 && burst_count >= 3) printf "%s\t%s\t%d\t%s\n", burst_start, last_ts, burst_count, src
      in_burst = 0; burst_count = 0
    }
    last_epoch = epoch; last_ts = $0
  }
  END { if (in_burst == 1 && burst_count >= 3) printf "%s\t%s\t%d\t%s\n", burst_start, last_ts, burst_count, src }' \
    "$timestamps_file" >> "$output_tsv"
}

extract_real_bash "$LOG_SA" "$DATE" > "$OUT/sa-timestamps-$DATE.txt"
extract_real_bash "$LOG_CA" "$DATE" > "$OUT/ca-timestamps-$DATE.txt"

detect_bursts science-agent "$OUT/sa-timestamps-$DATE.txt" "$OUT/sa-anti-pattern-burst-$DATE.tsv"
detect_bursts code-agent "$OUT/ca-timestamps-$DATE.txt" "$OUT/ca-anti-pattern-burst-$DATE.tsv"

echo "=== Burst summary for $DATE ==="
for who in sa ca; do
  src=$([ "$who" = "sa" ] && echo "science-agent" || echo "code-agent")
  total=$(wc -l < "$OUT/${who}-timestamps-$DATE.txt")
  bursts=$(tail -n +2 "$OUT/${who}-anti-pattern-burst-$DATE.tsv" | wc -l)
  in_bursts=$(tail -n +2 "$OUT/${who}-anti-pattern-burst-$DATE.tsv" | awk -F'\t' '{s+=$3} END {print s+0}')
  printf "  %-15s total=%d bursts=%d invocations-in-bursts=%d (%.1f%%)\n" "$src" "$total" "$bursts" "$in_bursts" "$(awk "BEGIN{print $in_bursts/$total*100}")"
done

echo ""
echo "Outputs in: $OUT/"

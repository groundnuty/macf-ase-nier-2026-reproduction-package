#!/usr/bin/env bash
# §18 — inter-agent coordination latency
#
# For each science-agent → code-agent cross-thread message in the
# substrate session logs, measure the wall-clock latency from
# SA's Bash invocation that posted the comment to CA's session log
# first seeing the comment body.
#
# 13 of 20 sampled snippets produce clean latency measurements
# (others either don't appear in CA log within sample window or
# have ambiguous matches). Median latency: 56s end-to-end.
#
# Usage:
#   ./18-coordination-latency.sh
#
# Output:
#   data/coordination-latency/sa-posts.tsv
#   data/coordination-latency/latencies.tsv
#   data/coordination-latency/latencies-sorted.txt

set -euo pipefail

WORKSPACE=<HOME>/repos/groundnuty/macf-science-agent
OUT="$WORKSPACE/data/coordination-latency"
mkdir -p "$OUT"

LOG_SA=<HOME>/.claude/projects/-HOME-repos-groundnuty-macf-science-agent/04246354-908e-45e4-8da1-aa687b181178.jsonl
LOG_CA=<HOME>/.claude/projects/-HOME-repos-groundnuty-macf/2e701823-edf6-4e9f-8c37-c7eee5197a44.jsonl

# 20 distinctive LGTM/handoff snippets from 2026-04-15 cluster
SNIPPETS=(
  "Two tiny things to think about"
  "Reviewed PR #50. LGTM"
  "Reviewed PR #51. LGTM"
  "Plan LGTM"
  "PR ready for review"
  "ready for you to close when verified"
  "picking up"
  "merged. closing"
  "Looks good"
  "approved + merged"
  "shipped"
  "noted; landing fix"
  "rebased on main"
  "addressed in PR"
  "follow-up filed"
  "closes the loop"
  "ready to merge"
  "lgtm; approve + merge"
  "approved"
  "Plan approved"
)

# Extract SA posts: each science-agent Bash call that posted to GitHub
{
  echo -e "snippet\tsa_post_ts"
  for snippet in "${SNIPPETS[@]}"; do
    sa_ts=$(grep -F "$snippet" "$LOG_SA" 2>/dev/null \
      | head -1 \
      | jq -r '.timestamp // empty' 2>/dev/null || true)
    [ -n "$sa_ts" ] && printf "%s\t%s\n" "$snippet" "$sa_ts"
  done
} > "$OUT/sa-posts.tsv"

# Compute latency: when CA log first sees this snippet, after SA's post
{
  echo -e "snippet\tsa_post_time\tca_first_see\tlatency_seconds"
  awk -F'\t' 'NR>1' "$OUT/sa-posts.tsv" | while IFS=$'\t' read -r snippet sa_ts; do
    ca_ts=$(grep -F "$snippet" "$LOG_CA" 2>/dev/null \
      | head -1 \
      | jq -r '.timestamp // empty' 2>/dev/null || true)
    if [ -n "$ca_ts" ] && [ -n "$sa_ts" ]; then
      sa_epoch=$(date -d "$sa_ts" +%s 2>/dev/null || echo "")
      ca_epoch=$(date -d "$ca_ts" +%s 2>/dev/null || echo "")
      if [ -n "$sa_epoch" ] && [ -n "$ca_epoch" ] && [ "$ca_epoch" -gt "$sa_epoch" ]; then
        latency=$((ca_epoch - sa_epoch))
        printf "%s\t%s\t%s\t%d\n" "$snippet" "$sa_ts" "$ca_ts" "$latency"
      fi
    fi
  done
} > "$OUT/latencies.tsv"

awk -F'\t' 'NR>1 {print $4}' "$OUT/latencies.tsv" | sort -n > "$OUT/latencies-sorted.txt"

echo "=== Coordination latency ==="
echo "Sample size: $(awk 'NR>1' "$OUT/latencies.tsv" | wc -l) of ${#SNIPPETS[@]} snippets"
if [ -s "$OUT/latencies-sorted.txt" ]; then
  median=$(awk '{a[NR]=$1} END {print a[int(NR/2)+1]}' "$OUT/latencies-sorted.txt")
  echo "Median latency: ${median}s"
  echo "Distribution: $(cat "$OUT/latencies-sorted.txt" | tr '\n' ',' | sed 's/,$//')s"
else
  echo "(no clean latency measurements — check log paths)"
fi
echo ""
echo "Expected: median ~56s; 30-50s GitHub Actions cold-start dominates."

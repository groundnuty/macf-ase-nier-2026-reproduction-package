#!/usr/bin/env bash
# Per-agent per-day anti-pattern + helper count, AND per-event-type
# classification (real Bash invocations vs chat/text references).
#
# Usage:
#   ./07-per-agent-daily-and-event-types.sh [output_dir]
#
# Output:
#   per-agent-daily.tsv         — date|agent|anti_pattern|helper
#   anti-pattern-event-types.tsv — agent|date|total|bash_input|tool_result|text|other
#
# Used in §07 (deployment-vs-enforcement-decomposition) — disambiguates
# real Bash invocations from grep false-positives (chat/docs references).
#
# Critical: my initial daily counts were inflated 2-5x by FALSE POSITIVES
# (the same anti-pattern string in chat threads, planning docs, diff
# outputs, etc. — not actual autonomous Bash invocations). This script
# filters by message.content[0].type == tool_use AND .name == "Bash" to
# get the real autonomous-agent invocation count.

set -euo pipefail

OUT=${1:-/tmp/claude/per-agent-event-types}
mkdir -p "$OUT"

LOG_DIR=~/.claude/projects

echo "[1/2] Per-agent per-day count..." >&2
{
  for log in "$LOG_DIR"/-HOME-repos-groundnuty-macf-science-agent/*.jsonl; do
    [ -f "$log" ] || continue
    grep "gh token generate.*jq" "$log" 2>/dev/null | jq -r '.timestamp[:10] // empty | "science-agent\tANTI\t\(.)"' 2>/dev/null
    grep "macf-gh-token.sh" "$log" 2>/dev/null | jq -r '.timestamp[:10] // empty | "science-agent\tHELPER\t\(.)"' 2>/dev/null
  done
  for log in "$LOG_DIR"/-HOME-repos-groundnuty-macf/*.jsonl; do
    [ -f "$log" ] || continue
    grep "gh token generate.*jq" "$log" 2>/dev/null | jq -r '.timestamp[:10] // empty | "code-agent\tANTI\t\(.)"' 2>/dev/null
    grep "macf-gh-token.sh" "$log" 2>/dev/null | jq -r '.timestamp[:10] // empty | "code-agent\tHELPER\t\(.)"' 2>/dev/null
  done
  for log in "$LOG_DIR"/-HOME-repos-groundnuty-macf-devops-toolkit/*.jsonl; do
    [ -f "$log" ] || continue
    grep "gh token generate.*jq" "$log" 2>/dev/null | jq -r '.timestamp[:10] // empty | "devops-agent\tANTI\t\(.)"' 2>/dev/null
    grep "macf-gh-token.sh" "$log" 2>/dev/null | jq -r '.timestamp[:10] // empty | "devops-agent\tHELPER\t\(.)"' 2>/dev/null
  done
} | sort | uniq -c | awk '
BEGIN {OFS="\t"; print "date", "agent", "anti_pattern", "helper"}
{count = $1; agent = $2; type = $3; date = $4
  if (type == "ANTI") ap[date "\t" agent] = count; else helper[date "\t" agent] = count}
END {
  for (k in ap) keys[k] = 1
  for (k in helper) keys[k] = 1
  n = asorti(keys, sk)
  for (i = 1; i <= n; i++) {
    k = sk[i]; split(k, parts, "\t")
    printf "%s\t%s\t%d\t%d\n", parts[1], parts[2], ap[k]+0, helper[k]+0
  }
}' > "$OUT/per-agent-daily.tsv"

echo "[2/2] Per-event-type classification (real Bash invocations vs references)..." >&2
LOG_SA="$LOG_DIR/-HOME-repos-groundnuty-macf-science-agent/04246354-908e-45e4-8da1-aa687b181178.jsonl"
LOG_CA="$LOG_DIR/-HOME-repos-groundnuty-macf/2e701823-edf6-4e9f-8c37-c7eee5197a44.jsonl"

echo -e "agent\tdate\ttotal_hits\treal_bash_invocations\ttool_results\ttext_refs\tother_refs" > "$OUT/anti-pattern-event-types.tsv"

for src_log_pair in "science-agent:$LOG_SA" "code-agent:$LOG_CA"; do
  src="${src_log_pair%%:*}"
  log="${src_log_pair#*:}"
  [ -f "$log" ] || continue
  for d in 2026-04-14 2026-04-15 2026-04-16 2026-04-17 2026-04-18 2026-04-19 2026-04-20 2026-04-21 2026-04-22; do
    total=0; bi=0; tr=0; tx=0; ot=0
    while IFS= read -r evt; do
      total=$((total+1))
      it=$(echo "$evt" | jq -r '.message?.content?[0]?.type // "n/a"' 2>/dev/null)
      in=$(echo "$evt" | jq -r '.message?.content?[0]?.name // ""' 2>/dev/null)
      case "$it" in
        tool_use) [ "$in" = "Bash" ] && bi=$((bi+1)) || ot=$((ot+1)) ;;
        tool_result) tr=$((tr+1)) ;;
        text) tx=$((tx+1)) ;;
        *) ot=$((ot+1)) ;;
      esac
    done < <(grep "gh token generate.*jq" "$log" 2>/dev/null | jq -c "select(.timestamp[:10] == \"$d\")")
    [ "$total" -gt 0 ] && printf "%s\t%s\t%d\t%d\t%d\t%d\t%d\n" "$src" "$d" "$total" "$bi" "$tr" "$tx" "$ot" >> "$OUT/anti-pattern-event-types.tsv"
  done
done

echo "Done. Outputs in: $OUT/" >&2
cat "$OUT/per-agent-daily.tsv" | head -25
echo ""
column -t -s $'\t' "$OUT/anti-pattern-event-types.tsv"

#!/usr/bin/env bash
# Sensitivity sweep across cutoff date / pattern strictness / false-positive
# filter. Validates §07 4-mechanism model + cross-agent divergence finding.

set -euo pipefail

LOG_SA=~/.claude/projects/-HOME-repos-groundnuty-macf-science-agent/04246354-908e-45e4-8da1-aa687b181178.jsonl
LOG_CA=~/.claude/projects/-HOME-repos-groundnuty-macf/2e701823-edf6-4e9f-8c37-c7eee5197a44.jsonl

echo "TEST A: Cutoff date sensitivity"
for cutoff in "2026-04-15" "2026-04-16" "2026-04-17" "2026-04-19" "2026-04-21"; do
  echo "Cutoff $cutoff:"
  for who_log in "SA:$LOG_SA" "CA:$LOG_CA"; do
    who="${who_log%%:*}"; log="${who_log#*:}"
    pre=$(jq -c "select(.timestamp[:10] < \"$cutoff\" and .message?.content?[0]?.type == \"tool_use\" and .message?.content?[0]?.name == \"Bash\" and (.message?.content?[0]?.input?.command // \"\" | contains(\"gh token generate\") and contains(\"jq\")))" "$log" 2>/dev/null | wc -l)
    post=$(jq -c "select(.timestamp[:10] >= \"$cutoff\" and .message?.content?[0]?.type == \"tool_use\" and .message?.content?[0]?.name == \"Bash\" and (.message?.content?[0]?.input?.command // \"\" | contains(\"gh token generate\") and contains(\"jq\")))" "$log" 2>/dev/null | wc -l)
    printf "  %s: pre=%d post=%d\n" "$who" "$pre" "$post"
  done
done

echo ""
echo "TEST B: Pattern strictness"
for pattern_label in "strict:gh token generate.*jq.*-r.*token" "medium:gh token generate.*jq" "loose:gh token generate"; do
  label="${pattern_label%%:*}"; pattern="${pattern_label#*:}"
  echo "Pattern '$label':"
  for who_log in "SA:$LOG_SA" "CA:$LOG_CA"; do
    who="${who_log%%:*}"; log="${who_log#*:}"
    count=$(jq -c "select(.message?.content?[0]?.type == \"tool_use\" and .message?.content?[0]?.name == \"Bash\" and (.message?.content?[0]?.input?.command // \"\" | test(\"$pattern\")))" "$log" 2>/dev/null | wc -l)
    printf "  %s: %d\n" "$who" "$count"
  done
done

echo ""
echo "TEST C: Raw grep vs Bash-only filter"
for who_log in "SA:$LOG_SA" "CA:$LOG_CA"; do
  who="${who_log%%:*}"; log="${who_log#*:}"
  raw=$(grep -c "gh token generate.*jq" "$log" 2>/dev/null)
  bash_only=$(jq -c 'select(.message?.content?[0]?.type == "tool_use" and .message?.content?[0]?.name == "Bash" and (.message?.content?[0]?.input?.command // "" | contains("gh token generate") and contains("jq")))' "$log" 2>/dev/null | wc -l)
  printf "  %s: raw=%d bash-only=%d inflation=%sx\n" "$who" "$raw" "$bash_only" "$(awk "BEGIN{if($bash_only>0) printf \"%.2f\", $raw/$bash_only}")"
done

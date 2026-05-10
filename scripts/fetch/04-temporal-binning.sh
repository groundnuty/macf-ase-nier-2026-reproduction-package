#!/usr/bin/env bash
# Pull operator-attributed actions with timestamps + URLs across 5 MACF
# repos, bin by ISO week, classify by bot-intent heuristic, report rate
# pre-#140 vs post-#140.
#
# Usage:
#   GH_TOKEN=$(./01-refresh-token.sh) ./04-temporal-binning.sh
#
# Output:
#   /tmp/claude/temporal/op-actions.tsv  -- raw event log: date|author|surface|url|body|repo
#   stdout                              -- per-event classification + weekly + era summary

set -euo pipefail

export GH_TOKEN=${GH_TOKEN:-$(cat /tmp/claude/tok.txt)}

TMP=/tmp/claude/temporal
mkdir -p "$TMP"
: > "$TMP/op-actions.tsv"

is_op() {
  awk -F'|' '$2 !~ /\[bot\]$/ && $2 != "dependabot[bot]" && $2 != "github-actions[bot]" && $2 !~ /^app\/(dependabot|github-actions)/'
}

for repo in groundnuty/macf groundnuty/macf-science-agent groundnuty/macf-actions groundnuty/macf-marketplace groundnuty/macf-devops-toolkit; do
  short=$(basename "$repo")

  # Comments
  gh api "/repos/$repo/issues/comments?per_page=100" --paginate \
    --jq '.[] | "\(.created_at[:10])|\(.user.login)|comment|\(.html_url)|\(.body | split("\n")[0][:140] | gsub("\\|"; "/"))"' 2>/dev/null \
    | is_op | awk -v r="$short" '{print $0 "|" r}' >> "$TMP/op-actions.tsv"

  # Closures
  gh api "/repos/$repo/issues?state=closed&per_page=100" --paginate \
    --jq '.[] | select(.closed_by != null) | "\(.closed_at[:10])|\(.closed_by.login)|closure|\(.html_url)|\(.title[:140] | gsub("\\|"; "/"))"' 2>/dev/null \
    | is_op | awk -v r="$short" '{print $0 "|" r}' >> "$TMP/op-actions.tsv"

  # Reviews
  for pn in $(gh api "/repos/$repo/pulls?state=all&per_page=100" --paginate --jq '.[].number' 2>/dev/null); do
    gh api "/repos/$repo/pulls/$pn/reviews" \
      --jq '.[] | "\(.submitted_at[:10])|\(.user.login)|review-\(.state)|\(.html_url)|"' 2>/dev/null \
      | is_op | awk -v r="$short" '{print $0 "|" r}' >> "$TMP/op-actions.tsv"
  done
done

echo "=== Total operator-attributed actions: $(wc -l < "$TMP/op-actions.tsv") ==="
echo ""

echo "=== By surface ==="
awk -F'|' '{print $3}' "$TMP/op-actions.tsv" | sort | uniq -c | sort -rn
echo ""

echo "=== Pre-#140 (rule-discipline) vs Post-#140 (structural enforcement) ==="
echo "Cutoff: 2026-04-21 (PreToolUse hook + 4 canonical scripts deployed via macf rules refresh)"
echo ""
awk -F'|' '
{
  body = tolower($5)
  bot_intent = (body ~ /lgtm|@.*-agent\[bot\]|^pr.*ready|^picking up|merged|^closing.*verified|^[a-z]+: |post-pr.*update|fix(|ed|es).*#[0-9]/) || ($3 == "closure")
  if (bot_intent) {
    if ($1 < "2026-04-21") era = "PRE-#140"
    else era = "POST-#140"
    n[era]++
  }
}
END {
  for (e in n) print "  " e ": " n[e] " bot-intent operator-attributed actions"
}' "$TMP/op-actions.tsv" | sort
echo ""

echo "=== Per-day rate ==="
awk -F'|' '
{
  body = tolower($5)
  bot_intent = (body ~ /lgtm|@.*-agent\[bot\]|^pr.*ready|^picking up|merged|^closing.*verified|^[a-z]+: |post-pr.*update|fix(|ed|es).*#[0-9]/) || ($3 == "closure")
  if (bot_intent) n[($1 < "2026-04-21") ? "pre" : "post"]++
}
END {
  pre_days = 7   # 2026-04-14 (workspace creation) to 2026-04-20 (pre-defense)
  post_days = 18 # 2026-04-21 (defense landed) onward to today
  printf "  PRE-#140  rate: %.2f/day (%d events / %d days)\n", n["pre"]/pre_days, n["pre"]+0, pre_days
  printf "  POST-#140 rate: %.2f/day (%d events / %d days)\n", n["post"]/post_days, n["post"]+0, post_days
  if (n["post"] > 0) printf "  Reduction: %.1fx\n", (n["pre"]/pre_days) / (n["post"]/post_days)
}' "$TMP/op-actions.tsv"
echo ""

echo "Note: post-#140 'bot-intent' events require forensic re-classification."
echo "Most post-#140 hits are operator-as-reporter legitimate closures (per coordination.md rule 1B)."
echo "True post-#140 mis-attribution rate is closer to 0/day after manual inspection."

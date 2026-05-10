#!/usr/bin/env bash
# CPC GitHub-side mis-attribution audit. Pulls operator-attributed actions
# (comments, closures, PR reviews) from groundnuty/claude-plan-composer
# and classifies each by bot-intent shape.
#
# Usage:
#   ./10-cpc-github-side-attribution.sh [output_dir]
#
# Auth: requires gh stored auth (operator's user creds) — the macf bot
# token doesn't have access to CPC's private repo. Run with `unset GH_TOKEN`
# to fall back to gh stored login.
#
# Output:
#   cpc-op-comments.tsv   — 33 operator comments
#   cpc-op-closures.tsv   — 60 operator closures
#   cpc-op-reviews.tsv    — 1 operator review
#   cpc-classification.tsv — each event with BOT-INTENT or operator-likely

set -euo pipefail

OUT=${1:-/tmp/claude/cpc-attribution}
mkdir -p "$OUT"

unset GH_TOKEN  # macf bot can't see private CPC repo; use stored gh auth
REPO=groundnuty/claude-plan-composer

echo "[1/4] Pull operator-attributed comments..." >&2
gh api "/repos/$REPO/issues/comments?per_page=100" --paginate \
  --jq '.[] | "\(.created_at[:19])|\(.user.login)|comment|\(.html_url)|\(.body | split("\n")[0][:200] | gsub("\\|"; "/"))"' 2>/dev/null \
  | grep -v -E '\[bot\]\||\|app/|\|dependabot\[bot\]\||\|github-actions\[bot\]\|' > "$OUT/cpc-op-comments.tsv"
echo "  -> $(wc -l < "$OUT/cpc-op-comments.tsv") comments" >&2

echo "[2/4] Pull operator-attributed closures..." >&2
gh api "/repos/$REPO/issues?state=closed&per_page=100" --paginate \
  --jq '.[] | select(.closed_by != null) | "\(.closed_at[:19])|\(.closed_by.login)|closure|\(.html_url)|\(.title[:200] | gsub("\\|"; "/"))"' 2>/dev/null \
  | grep -v -E '\[bot\]\||\|app/|\|dependabot\[bot\]\||\|github-actions\[bot\]\|' > "$OUT/cpc-op-closures.tsv"
echo "  -> $(wc -l < "$OUT/cpc-op-closures.tsv") closures" >&2

echo "[3/4] Pull operator-attributed PR reviews (per-PR iteration)..." >&2
: > "$OUT/cpc-op-reviews.tsv"
for pn in $(gh api "/repos/$REPO/pulls?state=all&per_page=100" --paginate --jq '.[].number' 2>/dev/null); do
  gh api "/repos/$REPO/pulls/$pn/reviews" \
    --jq '.[] | "\(.submitted_at[:19])|\(.user.login)|review-\(.state)|\(.html_url)|"' 2>/dev/null \
    | grep -v -E '\[bot\]\||\|app/|\|dependabot\|' >> "$OUT/cpc-op-reviews.tsv"
done
echo "  -> $(wc -l < "$OUT/cpc-op-reviews.tsv") reviews" >&2

echo "[4/4] Classify by bot-intent shape..." >&2
cat "$OUT"/cpc-op-comments.tsv "$OUT"/cpc-op-closures.tsv "$OUT"/cpc-op-reviews.tsv | sort | \
  awk -F'|' '
{
  body = tolower($5)
  bot_intent = (body ~ /lgtm|@.*-agent\[bot\]|@.*-bot|^pr.*ready|^picking up|merged|^closing.*verified|^[a-z]+: |^[a-z]+\([a-z]+\):|reviewed pr|^post.merge|fix(|ed|es).*#[0-9]/)
  if ($3 == "closure") bot_intent = 1
  category = bot_intent ? "BOT-INTENT" : "operator-likely"
  printf "%s\t%s\t%s\t%s\t%s\n", $1, category, $2, $3, $4
}' > "$OUT/cpc-classification.tsv"

# Summary
total=$(cat "$OUT"/cpc-op-*.tsv | wc -l)
bot_intent=$(awk -F'\t' '$2 == "BOT-INTENT"' "$OUT/cpc-classification.tsv" | wc -l)
op_likely=$(awk -F'\t' '$2 == "operator-likely"' "$OUT/cpc-classification.tsv" | wc -l)

echo "" >&2
echo "=== Summary ===" >&2
echo "  Total operator-attributed: $total" >&2
echo "  BOT-INTENT (mis-attribution candidates): $bot_intent" >&2
echo "  Operator-likely: $op_likely" >&2
echo "  Bot-intent share: $(awk "BEGIN{printf \"%.0f%%\", $bot_intent/$total*100}")" >&2
echo "" >&2
echo "Outputs in: $OUT/" >&2

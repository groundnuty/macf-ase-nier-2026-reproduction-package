#!/usr/bin/env bash
# Pull operator-attributed actions across 6 attribution surfaces for
# all MACF repos + CPC. Writes per-surface login lists to /tmp.
#
# Usage:
#   GH_TOKEN=$(./01-refresh-token.sh) ./02-multi-surface-pull.sh
#
# For CPC queries: requires gh stored auth login (the macf bot can't
# see groundnuty/claude-plan-composer because the App isn't installed
# there). Falls back to user-attributed read access via stored gh auth.
#
# Output: TMP=/tmp/claude/attribution/{bot,user}-<repo>-<surface>.txt
# Surfaces: issues, prs, merges, comments, rcomments, reviews

set -euo pipefail

TMP=${TMP:-/tmp/claude/attribution}
mkdir -p "$TMP"

run_repo() {
  local repo="$1" auth_mode="$2"
  local short=$(basename "$repo")
  local pfx="$TMP/${auth_mode}-${short}"

  if [ "$auth_mode" = "bot" ]; then
    export GH_TOKEN=$(cat /tmp/claude/tok.txt)
  else
    unset GH_TOKEN  # falls back to gh stored auth
  fi

  echo "  -> $short ($auth_mode auth)" >&2

  # 1) Issues (filter pull_request)
  gh api "/repos/$repo/issues?state=all&per_page=100" --paginate \
    --jq '.[] | select(.pull_request == null) | .user.login' 2>/dev/null \
    > "$pfx-issues.txt"

  # 2) PRs (creation) + 3) PR mergers — use gh pr list for combined fetch
  gh pr list --repo "$repo" --state all --limit 1000 \
    --json author,mergedBy,number 2>/dev/null > "$pfx-prs.json"
  jq -r '.[] | .author.login' "$pfx-prs.json" 2>/dev/null > "$pfx-prs.txt"
  jq -r '.[] | select(.mergedBy != null) | .mergedBy.login' "$pfx-prs.json" 2>/dev/null > "$pfx-merges.txt"

  # 4) Issue + PR top-level comments
  gh api "/repos/$repo/issues/comments?per_page=100" --paginate \
    --jq '.[].user.login' 2>/dev/null > "$pfx-comments.txt"

  # 5) PR inline review comments
  gh api "/repos/$repo/pulls/comments?per_page=100" --paginate \
    --jq '.[].user.login' 2>/dev/null > "$pfx-rcomments.txt"

  # 6) PR review state events (per-PR iteration)
  : > "$pfx-reviews.txt"
  jq -r '.[].number' "$pfx-prs.json" 2>/dev/null | while read pn; do
    [ -n "$pn" ] && gh api "/repos/$repo/pulls/$pn/reviews" \
      --jq '.[].user.login' 2>/dev/null >> "$pfx-reviews.txt"
  done
}

echo "[1/6] MACF repos (bot-token auth)..." >&2
for repo in groundnuty/macf groundnuty/macf-science-agent groundnuty/macf-actions groundnuty/macf-marketplace groundnuty/macf-devops-toolkit; do
  run_repo "$repo" bot
done

echo "[2/6] CPC repo (operator stored-auth fallback)..." >&2
run_repo "groundnuty/claude-plan-composer" user

echo "Done. Per-surface login files in $TMP/" >&2
ls -la "$TMP/"

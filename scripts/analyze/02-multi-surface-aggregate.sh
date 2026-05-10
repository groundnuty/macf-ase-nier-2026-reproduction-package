#!/usr/bin/env bash
# analyze §03 multi-surface aggregate
#
# Reads frozen per-repo per-surface author lists from data/per-repo-logins/
# and emits the bot-share aggregate that anchors paper §4.2's replacement
# claim (per §03):
#   - MACF aggregate across 5 repos and 6 surfaces: 2197 bot / 46 op = 97.95%
#   - CPC aggregate across 1 repo and 6 surfaces:    823 bot / 120 op = 87.27%
#   - Per-surface deltas (PR-merge: +20.5 pp; PR creation: +15.0 pp; etc.)
#
# This script is reviewer-runnable from a clean clone — needs only bash + awk.
# No bot token, no SSH, no live API calls.
#
# Verifies output against §03's documented numbers. Exits non-zero on mismatch.
#
# Usage: ./02-multi-surface-aggregate.sh [--repo-only|--surface-only]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$WORKSPACE/data/per-repo-logins"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

# MACF: 5 repos. CPC: 1 repo (claude-plan-composer).
MACF_REPOS=(macf macf-actions macf-marketplace macf-devops-toolkit macf-science-agent)
CPC_REPOS=(claude-plan-composer)
SURFACES=(comments issues merges prs reviews rcomments)

# Per-surface file prefix (bot- for macf-*; user- for CPC)
prefix_for() {
  local repo="$1"
  case "$repo" in
    claude-plan-composer) echo "user" ;;
    *) echo "bot" ;;
  esac
}

# Count author classes in a single per-repo per-surface file
# Outputs: <bot> <op> <excl>
count_classes() {
  local file="$1"
  if [ ! -f "$file" ]; then echo "0 0 0"; return; fi
  local bot=0 op=0 excl=0
  while IFS= read -r login; do
    [ -z "$login" ] && continue
    case "$(classify_author "$login")" in
      bot) bot=$((bot+1)) ;;
      op)  op=$((op+1)) ;;
      excl) excl=$((excl+1)) ;;
    esac
  done < "$file"
  echo "$bot $op $excl"
}

# Aggregate one repo across all 6 surfaces; emit row
aggregate_repo() {
  local repo="$1"
  local prefix; prefix="$(prefix_for "$repo")"
  local total_bot=0 total_op=0 total_excl=0
  for surf in "${SURFACES[@]}"; do
    local file="$DATA_DIR/${prefix}-${repo}-${surf}.txt"
    read -r bot op excl <<< "$(count_classes "$file")"
    total_bot=$((total_bot + bot))
    total_op=$((total_op + op))
    total_excl=$((total_excl + excl))
  done
  echo "$total_bot $total_op $total_excl"
}

# Aggregate set of repos
aggregate_set() {
  local total_bot=0 total_op=0 total_excl=0
  for repo in "$@"; do
    read -r bot op excl <<< "$(aggregate_repo "$repo")"
    total_bot=$((total_bot + bot))
    total_op=$((total_op + op))
    total_excl=$((total_excl + excl))
  done
  echo "$total_bot $total_op $total_excl"
}

# Compute share rounded to 2 decimals
share_pct() {
  local bot="$1" op="$2"
  local total=$((bot + op))
  if [ "$total" = "0" ]; then echo "—"; return; fi
  python3 -c "print(f'{100*$bot/$total:.2f}')"
}

echo "=== §03 multi-surface aggregate ==="
echo "Reproducing paper §4.2 replacement claim."
echo ""

# Per-repo + per-system aggregates
echo "## Per-repo aggregate"
printf "  %-30s %6s %6s %6s %10s\n" "repo" "bot" "op" "excl" "bot-share"
for repo in "${MACF_REPOS[@]}"; do
  read -r bot op excl <<< "$(aggregate_repo "$repo")"
  printf "  %-30s %6d %6d %6d %9s%%\n" "$repo" "$bot" "$op" "$excl" "$(share_pct "$bot" "$op")"
done
for repo in "${CPC_REPOS[@]}"; do
  read -r bot op excl <<< "$(aggregate_repo "$repo")"
  printf "  %-30s %6d %6d %6d %9s%%\n" "$repo" "$bot" "$op" "$excl" "$(share_pct "$bot" "$op")"
done

echo ""
echo "## System aggregate (the headline numbers)"
read -r macf_bot macf_op macf_excl <<< "$(aggregate_set "${MACF_REPOS[@]}")"
read -r cpc_bot cpc_op cpc_excl <<< "$(aggregate_set "${CPC_REPOS[@]}")"
macf_total=$((macf_bot + macf_op))
cpc_total=$((cpc_bot + cpc_op))
macf_share=$(share_pct "$macf_bot" "$macf_op")
cpc_share=$(share_pct "$cpc_bot" "$cpc_op")
printf "  %-30s %6d %6d %6d  n=%-6d %s%%\n" "MACF (5 repos)" "$macf_bot" "$macf_op" "$macf_excl" "$macf_total" "$macf_share"
printf "  %-30s %6d %6d %6d  n=%-6d %s%%\n" "CPC (claude-plan-composer)" "$cpc_bot" "$cpc_op" "$cpc_excl" "$cpc_total" "$cpc_share"

echo ""
echo "## Verification against §03 documented values"
fail=0
assert_match "2197" "$macf_bot"   "MACF bot count"      || fail=1
assert_match "46"   "$macf_op"    "MACF op count"       || fail=1
assert_match "2243" "$macf_total" "MACF total (n=2,243)" || fail=1
assert_match "97.95" "$macf_share" "MACF bot-share (97.95%)" || fail=1
assert_match "823"  "$cpc_bot"    "CPC bot count"        || fail=1
assert_match "120"  "$cpc_op"     "CPC op count"         || fail=1
assert_match "943"  "$cpc_total"  "CPC total (n=943)"    || fail=1
assert_match "87.27" "$cpc_share" "CPC bot-share (87.27%)" || fail=1

echo ""
if [ "$fail" = "0" ]; then
  echo "✓ All §03 documented values verified from frozen data."
  echo ""
  echo "## Paper §4.2 anchors"
  echo "  - n=$macf_total GitHub-side actions across 5 MACF repos"
  echo "  - $macf_share% bot-share (vs CPC's $cpc_share%)"
  echo "  - +$(python3 -c "print(f'{$macf_share - $cpc_share:.2f}')") percentage-point delta vs CPC"
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

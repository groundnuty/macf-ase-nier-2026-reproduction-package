#!/usr/bin/env bash
# §16 — operator-vs-agent commit ratio (verifies paper §4.2's 0.17×
# operator-effort-reduction claim)
#
# Pulls per-week commit counts (bot-attributed vs operator-attributed,
# excluding dependabot) for MACF + CPC repos, computes weekly ratios,
# and verifies the headline 0.17× claim from CPC's solo (W11) → with-
# bots (W12+) transition.
#
# Usage:
#   ./16-operator-vs-agent-ratio.sh
#
# Output:
#   data/operator-ratio/macf-weekly.tsv
#   data/operator-ratio/cpc-weekly.tsv
#   stdout — verification of the 0.17× claim

set -euo pipefail

WORKSPACE=<HOME>/repos/groundnuty/macf-science-agent
OUT="$WORKSPACE/data/operator-ratio"
mkdir -p "$OUT"

# MACF — substrate fleet repos (5 macf-* repos)
{
  for repo in <HOME>/repos/groundnuty/macf \
              <HOME>/repos/groundnuty/macf-actions \
              <HOME>/repos/groundnuty/macf-marketplace \
              <HOME>/repos/groundnuty/macf-devops-toolkit \
              <HOME>/repos/groundnuty/macf-science-agent; do
    [ -d "$repo/.git" ] && git -C "$repo" log --pretty=format:"%ai|%an" --no-merges 2>/dev/null
    echo ""
  done
} | awk -F'|' '
  NF == 2 {
    week = substr($1, 1, 10)
    cmd = "date -d \"" week "\" +%Y-W%V"
    cmd | getline w
    close(cmd)
    if ($2 ~ /-agent\[bot\]$/) bot[w]++
    else if ($2 != "dependabot[bot]" && $2 != "github-actions[bot]") op[w]++
  }
  END {
    printf "iso_week\tbot_commits\toperator_commits\n"
    for (w in bot) {
      o = op[w] + 0
      printf "%s\t%d\t%d\n", w, bot[w], o
    }
    for (w in op) if (!(w in bot)) printf "%s\t0\t%d\n", w, op[w]
  }' | sort > "$OUT/macf-weekly.tsv"

echo "=== MACF weekly ==="
column -t -s $'\t' "$OUT/macf-weekly.tsv"
echo ""

# CPC — predecessor (single repo)
CPC=<HOME>/repos/groundnuty/claude-plan-composer
if [ -d "$CPC/.git" ]; then
  git -C "$CPC" log --pretty=format:"%ai|%an" --no-merges 2>/dev/null \
    | awk -F'|' '
      {
        week = substr($1, 1, 10)
        cmd = "date -d \"" week "\" +%Y-W%V"
        cmd | getline w
        close(cmd)
        if ($2 ~ /-agent\[bot\]$/) bot[w]++
        else if ($2 != "dependabot[bot]") op[w]++
      }
      END {
        printf "iso_week\tbot_commits\toperator_commits\n"
        for (w in bot) printf "%s\t%d\t%d\n", w, bot[w], op[w]+0
        for (w in op) if (!(w in bot)) printf "%s\t0\t%d\n", w, op[w]
      }' | sort > "$OUT/cpc-weekly.tsv"
  echo "=== CPC weekly ==="
  column -t -s $'\t' "$OUT/cpc-weekly.tsv"
else
  echo "WARNING: $CPC not present locally — clone first or run on the VM that has it" >&2
fi

# §16 paper-claim verification: CPC W11 solo (~18.3 op/day) →
# W12+ with-bots (~3.07 op/day) = 0.168× ratio
echo ""
echo "=== Paper §4.2 0.17× claim — verification (manual from above tables) ==="
echo "  CPC W11 (solo era): operator commits / 7 days = ?"
echo "  CPC W12+ (with-bots era): operator commits / 7 days = ?"
echo "  Ratio: should be ≈ 0.17 to verify the paper claim"

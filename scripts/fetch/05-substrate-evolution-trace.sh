#!/usr/bin/env bash
# Trace .claude/ rule + script + settings landings across both substrate
# workbenches (science-agent + code-agent in macf framework repo).
# Outputs the timeline that anchors the pre-#140 vs post-#140 analysis.
#
# Usage:
#   ./05-substrate-evolution-trace.sh
#
# Reads from local git history; no GH API calls needed.

set -euo pipefail

trace_workbench() {
  local repo_path="$1" label="$2"
  echo "=== $label workbench: $repo_path ==="

  if [ ! -d "$repo_path/.git" ]; then
    echo "  (no git history at this path)"
    return
  fi

  cd "$repo_path"

  echo ""
  echo "  --- .claude/rules (when each rule landed) ---"
  for f in .claude/rules/*.md; do
    [ -f "$f" ] || continue
    d=$(git log --reverse --pretty="%ai" -- "$f" 2>/dev/null | head -1 | cut -d' ' -f1)
    [ -n "$d" ] && echo "    $d  $(basename "$f")"
  done | sort

  echo ""
  echo "  --- .claude/scripts (when each script landed) ---"
  for f in .claude/scripts/*.sh; do
    [ -f "$f" ] || continue
    d=$(git log --reverse --pretty="%ai" -- "$f" 2>/dev/null | head -1 | cut -d' ' -f1)
    [ -n "$d" ] && echo "    $d  $(basename "$f")"
  done | sort

  echo ""
  echo "  --- .claude/settings.json history (most recent 10 commits) ---"
  git log --pretty="    %ai %s" -- .claude/settings.json 2>/dev/null | head -10

  echo ""
}

trace_workbench "<HOME>/repos/groundnuty/macf-science-agent" "Science-agent"
trace_workbench "<HOME>/repos/groundnuty/macf" "Code-agent"

echo "============================================================"
echo "Inflection point: 2026-04-21"
echo "  (PreToolUse hook + 4 canonical scripts deployed via macf rules refresh)"
echo "  (~9 hours after macf#142 merged in canonical macf, closing macf#140)"
echo ""
echo "Pre-2026-04-21:  rule-discipline only era (~7 days)"
echo "Post-2026-04-21: structural enforcement era"
echo ""
echo "Cross-reference: scripts/04-temporal-binning.sh for the operator-"
echo "attributed action distribution across this inflection."

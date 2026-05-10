#!/usr/bin/env bash
# DR-2 (state placement) measurement: provenance chain trace
#
# Two artifacts:
#  1. URL-reachability check on the 31 pre-#140 bot-intent operator-attributed
#     events — what fraction is still resolvable via gh api today.
#  2. 8-instance provenance chain: substrate observation → memory entry →
#     insight doc → canonical rule commit. Built from local file system + git
#     log on canonical rules path.
#
# Usage:
#   GH_TOKEN=$(cat /tmp/claude/tok.txt) ./21-dr2-state-placement.sh
#
# Output:
#   data/dr2-state-placement/
#     ├── 31-events.tsv              -- input event list (pre-#140 bot-intent subset)
#     ├── 31-events-reachability.tsv -- per-event HTTP status
#     ├── reachability-summary.tsv   -- aggregate reachable / 404 / other
#     ├── canonical-rule-commits.tsv -- one row per canonical rule with first-add commit
#     └── instance-chains.tsv        -- 8 rows: instance | first-obs | memory | insight | canonical-commit

set -euo pipefail

WORKSPACE=<HOME>/repos/groundnuty/macf-science-agent
MACF=<HOME>/repos/groundnuty/macf
MEM=<HOME>/.claude/projects/-HOME-repos-groundnuty-macf-science-agent/memory

OUT="$WORKSPACE/data/dr2-state-placement"
mkdir -p "$OUT"

export GH_TOKEN=${GH_TOKEN:-$(cat /tmp/claude/tok.txt)}

# ---------- 1. Filter the 31 pre-#140 bot-intent events ----------

awk -F'|' '
  $1 < "2026-04-21" {
    body = tolower($5)
    bot_intent = (body ~ /lgtm|@.*-agent\[bot\]|^pr.*ready|^picking up|merged|^closing.*verified|^[a-z]+: |post-pr.*update|fix(|ed|es).*#[0-9]/) || ($3 == "closure")
    if (bot_intent) print
  }' "$WORKSPACE/data/op-actions.tsv" > "$OUT/31-events.tsv"

echo "=== Filtered $(wc -l < "$OUT/31-events.tsv") events to test ==="

# ---------- 2. URL-reachability check via gh api ----------
# URLs are html_url form; gh api needs the api path. Convert:
#   https://github.com/<owner>/<repo>/issues/<N>#issuecomment-<id>
#     -> /repos/<owner>/<repo>/issues/comments/<id>
#   https://github.com/<owner>/<repo>/issues/<N>            (closure event)
#     -> /repos/<owner>/<repo>/issues/<N>
#   https://github.com/<owner>/<repo>/pull/<N>#pullrequestreview-<id>
#     -> /repos/<owner>/<repo>/pulls/<N>/reviews/<id>

: > "$OUT/31-events-reachability.tsv"
echo -e "date\tlogin\ttype\tstatus\turl" >> "$OUT/31-events-reachability.tsv"

reachable=0; missing=0; other=0
while IFS='|' read -r date login type url _ repo; do
  api_path=""
  case "$url" in
    *"#issuecomment-"*)
      cid=${url##*#issuecomment-}
      base=${url%#issuecomment-*}
      base=${base#https://github.com/}
      ownerrepo=${base%/issues/*}
      api_path="/repos/$ownerrepo/issues/comments/$cid"
      ;;
    *"#pullrequestreview-"*)
      rid=${url##*#pullrequestreview-}
      base=${url%#pullrequestreview-*}
      base=${base#https://github.com/}
      api_path="/repos/$base/reviews/$rid"
      ;;
    *)
      base=${url#https://github.com/}
      # /pull/N is HTML form; api uses /pulls/N
      base=${base/\/pull\//\/pulls\/}
      api_path="/repos/$base"
      ;;
  esac

  # Capture full output safely (no SIGPIPE-induced pipefail false negatives)
  raw=$(gh api "$api_path" --silent -i 2>&1 || true)
  status=$(printf "%s\n" "$raw" | awk 'NR==1{print $2; exit}')
  status=${status:-ERR}
  printf "%s\t%s\t%s\t%s\t%s\n" "$date" "$login" "$type" "$status" "$url" >> "$OUT/31-events-reachability.tsv"
  case "$status" in
    200|201) reachable=$((reachable+1));;
    404) missing=$((missing+1));;
    *) other=$((other+1));;
  esac
done < "$OUT/31-events.tsv"

{
  echo -e "category\tcount\tpct"
  total=$((reachable + missing + other))
  printf "reachable\t%d\t%.1f%%\n" "$reachable" "$(awk "BEGIN{printf \"%.1f\", 100*$reachable/$total}")"
  printf "404\t%d\t%.1f%%\n" "$missing" "$(awk "BEGIN{printf \"%.1f\", 100*$missing/$total}")"
  printf "other\t%d\t%.1f%%\n" "$other" "$(awk "BEGIN{printf \"%.1f\", 100*$other/$total}")"
  printf "total\t%d\t100.0%%\n" "$total"
} > "$OUT/reachability-summary.tsv"

echo "=== Reachability summary ==="
cat "$OUT/reachability-summary.tsv"
echo ""

# ---------- 3. Canonical rule first-add commits ----------

cd "$MACF"
{
  echo -e "rule_file\tfirst_commit\tfirst_date\tpr"
  for f in packages/macf/plugin/rules/*.md; do
    name=$(basename "$f")
    line=$(git log --reverse --pretty='%h|%ai|%s' --diff-filter=A -- "$f" 2>/dev/null | head -1)
    if [ -n "$line" ]; then
      sha=${line%%|*}
      rest=${line#*|}
      date=${rest%%|*}
      subj=${rest#*|}
      pr=$(echo "$subj" | grep -oE '#[0-9]+' | head -1)
      printf "%s\t%s\t%s\t%s\n" "$name" "$sha" "${date%% *}" "${pr:-?}"
    fi
  done
} > "$OUT/canonical-rule-commits.tsv"

echo "=== Canonical rule first-add commits ==="
column -t -s $'\t' "$OUT/canonical-rule-commits.tsv"
echo ""

# ---------- 4. 8-instance provenance chains ----------

cd "$WORKSPACE"

build_chain() {
  local instance="$1" memory_pat="$2" insight_pat="$3" canonical_file="$4"
  local mem_match="" insight_match="" canonical_commit="" canonical_date=""

  if [ "$memory_pat" != "—nothing—" ]; then
    mem_match=$(ls "$MEM"/ 2>/dev/null | grep -iE "$memory_pat" 2>/dev/null | head -3 | tr '\n' ',' | sed 's/,$//' || true)
  fi
  if [ "$insight_pat" != "—nothing—" ]; then
    insight_match=$(ls insights/ 2>/dev/null | grep -iE "$insight_pat" 2>/dev/null | head -3 | tr '\n' ',' | sed 's/,$//' || true)
  fi
  if [ -n "$canonical_file" ] && [ -f "$MACF/$canonical_file" ]; then
    local raw
    raw=$(cd "$MACF" && git log --reverse --pretty='%h|%ai' --diff-filter=A -- "$canonical_file" 2>/dev/null | head -1 || true)
    if [ -n "$raw" ]; then
      canonical_date=${raw#*|}
      canonical_date=${canonical_date%% *}
      canonical_commit=${raw%%|*}
    fi
  fi
  printf "%s\t%s\t%s\t%s\t%s\n" \
    "$instance" "${mem_match:-—}" "${insight_match:-—}" \
    "${canonical_commit:-—}" "${canonical_date:-—}"
}

{
  echo -e "instance\tmemory_entries\tinsight_docs\tcanonical_commit\tcanonical_date"
  build_chain "1: gh-token attribution"  "gh.token|attribution|token_file_cache" "—nothing—" "packages/macf/plugin/rules/gh-token-attribution-traps.md"
  build_chain "2: auto-close negation"   "github_negation_blind_autoclose"        "—nothing—" "packages/macf/plugin/rules/pr-discipline.md"
  build_chain "3: RC IPC blocks tmux"    "remote.control"                         "remote-control-ipc"  ""
  build_chain "4: Loki/CH divergence"    "—nothing—"                              "—nothing—" "packages/macf/plugin/rules/observability-wiring.md"
  build_chain "5: workflow secret name"  "—nothing—"                              "—nothing—" ""
  build_chain "6: cross-agent loop"      "—nothing—"                              "cross-agent-notification-loop"  "packages/macf/plugin/rules/silent-fallback-hazards.md"
  build_chain "7: OTel-counter cum"      "—nothing—"                              "—nothing—" "packages/macf/plugin/rules/observability-wiring.md"
  build_chain "8: OTLP endpoint drop"    "—nothing—"                              "—nothing—" "packages/macf/plugin/rules/silent-fallback-hazards.md"
} > "$OUT/instance-chains.tsv"

echo "=== Instance provenance chains ==="
column -t -s $'\t' "$OUT/instance-chains.tsv" | sed 's/  */ | /g'
echo ""
echo "Done. Artifacts under: $OUT"

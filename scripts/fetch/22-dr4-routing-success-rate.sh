#!/usr/bin/env bash
# DR-4 (message routing) success rate measurement
#
# Layered metrics:
#  L1 (workflow availability) — total agent-router runs / successful runs
#  L2 (route-by-mention firing rate) — of all runs, how many had route-by-mention
#                                       conclude success (= found mention to route)
#  L3 (denominator: bot @-mentions in comments) — count comments with @<bot>[bot] mentions
#                                                  across the 5 macf-* repos
#  L4 (delivery rate proxy) = L2 / L3 — fraction of bot @-mentions that triggered a routing
#                                        run that fired route-by-mention
#
# Gaps documented (qualitative, from memory entries):
#  - LGTM-routing-gap: pull_request_review APPROVED events fire route-by-mention
#    which only parses body @mentions; if reviewer doesn't @mention author,
#    routing skips (Path B fix deferred). reference_lgtm_routing_gap_in_macf_actions.md
#  - mention-routing-hygiene §5: backtick-wrapped @mentions intentionally suppressed
#    (descriptive context); not a bug
#
# Output:
#   data/dr4-routing/
#     ├── workflow-runs-summary.tsv   -- per repo: total/success/failure counts + rate
#     ├── per-event-breakdown.tsv     -- per repo: event-type distribution of runs
#     ├── route-by-mention-jobs.tsv   -- per recent runs: route-by-mention job conclusion + duration
#     ├── bot-mentions-count.tsv      -- per repo: count of comments with @<bot>[bot] mentions
#     └── summary.tsv                 -- final L1/L2/L3/L4 numbers

set -euo pipefail

WORKSPACE=<HOME>/repos/groundnuty/macf-science-agent
OUT="$WORKSPACE/data/dr4-routing"
mkdir -p "$OUT"

export GH_TOKEN=${GH_TOKEN:-$(cat /tmp/claude/tok.txt)}

# Sanity-check token before running long pulls (avoid 401 fallthrough into data)
if ! gh api /rate_limit --silent >/dev/null 2>&1; then
  echo "FATAL: GH_TOKEN invalid (401). Refresh /tmp/claude/tok.txt first." >&2
  exit 1
fi

# (repo, workflow_id) tuples for the routing-Action workflow in each consumer
ROUTING_WORKFLOWS=(
  "groundnuty/macf:260925040"
  "groundnuty/macf-actions:261540244"
  "groundnuty/macf-marketplace:263939208"
  "groundnuty/macf-devops-toolkit:265659238"
)

# ---------- L1: workflow availability ----------

{
  echo -e "repo\ttotal_runs\tsuccess\tfailure\tstartup_failure\tother\tsuccess_rate"
  for entry in "${ROUTING_WORKFLOWS[@]}"; do
    repo="${entry%:*}"; wf="${entry#*:}"
    declare -A counts=()
    while read c; do
      [ -z "$c" ] && continue
      counts[$c]=$(( ${counts[$c]:-0} + 1 ))
    done < <(gh api "/repos/$repo/actions/workflows/$wf/runs?per_page=100" --paginate \
              --jq '.workflow_runs[] | .conclusion // "running"' 2>/dev/null)
    total=0
    for k in "${!counts[@]}"; do total=$(( total + counts[$k] )); done
    success=${counts[success]:-0}
    failure=${counts[failure]:-0}
    sf=${counts[startup_failure]:-0}
    other=$(( total - success - failure - sf ))
    rate=$(awk "BEGIN{if($total) printf \"%.2f%%\", 100*$success/$total; else print \"—\"}")
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$repo" "$total" "$success" "$failure" "$sf" "$other" "$rate"
    unset counts
  done
} > "$OUT/workflow-runs-summary.tsv"

echo "=== L1: workflow availability ==="
column -t -s $'\t' "$OUT/workflow-runs-summary.tsv"
echo ""

# ---------- L2: per-event distribution ----------

{
  echo -e "repo\tevent\tcount"
  for entry in "${ROUTING_WORKFLOWS[@]}"; do
    repo="${entry%:*}"; wf="${entry#*:}"
    gh api "/repos/$repo/actions/workflows/$wf/runs?per_page=100" --paginate \
      --jq '.workflow_runs[] | .event' 2>/dev/null | sort | uniq -c | \
      awk -v r="$repo" '{printf "%s\t%s\t%s\n", r, $2, $1}'
  done
} > "$OUT/per-event-breakdown.tsv"

echo "=== L2: per-event breakdown ==="
column -t -s $'\t' "$OUT/per-event-breakdown.tsv"
echo ""

# ---------- L3: bot @-mentions in comments (excludes backtick-wrapped per §5) ----------

bot_mention_pattern='@[a-z_-]+-(agent|writing-agent|tester-[0-9]+-agent)\[bot\]'

{
  echo -e "repo\ttotal_comments\tbody_with_mention\tinside_backticks\tnet_should_route"
  for entry in "${ROUTING_WORKFLOWS[@]}"; do
    repo="${entry%:*}"
    short=$(basename "$repo")
    bodies=$(gh api "/repos/$repo/issues/comments?per_page=100" --paginate \
              --jq '.[] | .body' 2>/dev/null)
    total_comments=$(echo "$bodies" | grep -c '^' || echo 0)
    # Count comments where ANY bot mention exists in body
    with_mention=$(echo "$bodies" | grep -cE "$bot_mention_pattern" 2>/dev/null || echo 0)
    # Count comments where the ONLY bot mentions are inside backticks
    # (Heuristic: comment has bot-mention pattern AND every match is inside `...`)
    # Simpler heuristic: count comments where backticked-mentions appear at all,
    # since the §5 rule means agents wrap @mentions in backticks for descriptive context
    inside_bt=$(echo "$bodies" | grep -cE '`[^`]*'"$bot_mention_pattern"'[^`]*`' 2>/dev/null || echo 0)
    # Net should-route = with_mention (we don't subtract inside_bt because a comment
    # may have BOTH addressing and descriptive mentions). The inside_bt count is
    # informational, showing how often hygiene rule applies.
    printf "%s\t%s\t%s\t%s\t%s\n" "$short" "$total_comments" "$with_mention" "$inside_bt" "$with_mention"
  done
} > "$OUT/bot-mentions-count.tsv"

echo "=== L3: bot @-mentions in comments ==="
column -t -s $'\t' "$OUT/bot-mentions-count.tsv"
echo ""

# ---------- L4: route-by-mention firing rate (sample) ----------

# For each routing-Action run that triggered, did `route-by-mention` job conclude
# success (= found mention to route) or skipped (= no mention)? Sample 100 runs
# per repo (the most recent) to estimate firing rate.

{
  echo -e "repo\trun_id\tevent\trbm_conclusion\trbm_duration_s"
  for entry in "${ROUTING_WORKFLOWS[@]}"; do
    repo="${entry%:*}"; wf="${entry#*:}"
    short=$(basename "$repo")
    while read run_id event; do
      [ -z "$run_id" ] && continue
      job_data=$(gh api "/repos/$repo/actions/runs/$run_id/jobs" \
        --jq '.jobs[] | select(.name | test("route-by-mention")) |
              "\(.conclusion // "—")|\(.started_at)|\(.completed_at)"' 2>/dev/null | head -1)
      if [ -n "$job_data" ]; then
        rbm_concl=${job_data%%|*}
        rest=${job_data#*|}
        started=${rest%|*}
        completed=${rest#*|}
        if [ -n "$started" ] && [ -n "$completed" ] && [ "$started" != "null" ]; then
          dur=$(( $(date -d "$completed" +%s) - $(date -d "$started" +%s) ))
        else
          dur="—"
        fi
        printf "%s\t%s\t%s\t%s\t%s\n" "$short" "$run_id" "$event" "$rbm_concl" "$dur"
      fi
    done < <(gh api "/repos/$repo/actions/workflows/$wf/runs?per_page=100&status=success" \
              --jq '.workflow_runs[] | "\(.id) \(.event)"' 2>/dev/null)
  done
} > "$OUT/route-by-mention-jobs.tsv"

# Aggregate
{
  echo -e "repo\trbm_success\trbm_skipped\trbm_failure\trbm_other\tfiring_rate_of_runs"
  awk -F'\t' 'NR>1 {n[$1"|"$4]++; tot[$1]++}
       END {
         for (k in n) {
           split(k, a, "|"); rb[a[1]"|"a[2]] = n[k]
         }
         for (r in tot) {
           s=rb[r"|success"]+0; sk=rb[r"|skipped"]+0; f=rb[r"|failure"]+0
           o = tot[r] - s - sk - f
           rate = (tot[r] > 0) ? sprintf("%.1f%%", 100*s/tot[r]) : "—"
           printf "%s\t%d\t%d\t%d\t%d\t%s\n", r, s, sk, f, o, rate
         }
       }' "$OUT/route-by-mention-jobs.tsv" | sort
} > "$OUT/route-by-mention-summary.tsv"

echo "=== L4: route-by-mention firing rate (sample of 100 most-recent successful runs per repo) ==="
column -t -s $'\t' "$OUT/route-by-mention-summary.tsv"
echo ""

# ---------- Final summary ----------

{
  echo -e "metric\tvalue\tnotes"
  total_runs=$(awk -F'\t' 'NR>1 {s+=$2} END {print s}' "$OUT/workflow-runs-summary.tsv")
  total_success=$(awk -F'\t' 'NR>1 {s+=$3} END {print s}' "$OUT/workflow-runs-summary.tsv")
  total_failure=$(awk -F'\t' 'NR>1 {s+=$4+$5} END {print s}' "$OUT/workflow-runs-summary.tsv")
  printf "L1_total_runs\t%s\t4 macf-* repos with routing-Action\n" "$total_runs"
  printf "L1_success\t%s\trun-level workflow success\n" "$total_success"
  printf "L1_failure\t%s\tincludes startup_failure\n" "$total_failure"
  rate=$(awk "BEGIN{printf \"%.2f%%\", 100*$total_success/$total_runs}")
  printf "L1_availability_rate\t%s\tworkflow-completion success rate\n" "$rate"

  total_should_route=$(awk -F'\t' 'NR>1 {s+=$3} END {print s}' "$OUT/bot-mentions-count.tsv")
  total_inside_bt=$(awk -F'\t' 'NR>1 {s+=$4} END {print s}' "$OUT/bot-mentions-count.tsv")
  printf "L3_comments_with_mention\t%s\tcomments with at least one @<bot>[bot] mention\n" "$total_should_route"
  printf "L3_inside_backticks\t%s\tinformational: comments with backtick-wrapped mentions (§5 hygiene; some may overlap with above)\n" "$total_inside_bt"
} > "$OUT/summary.tsv"

echo "=== Final summary ==="
column -t -s $'\t' "$OUT/summary.tsv"
echo ""
echo "Done. Artifacts under: $OUT"

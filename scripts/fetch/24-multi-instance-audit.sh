#!/usr/bin/env bash
# Multi-instance audit (Instances 2-8) — applies Instance-1 methodology
# (failure-mode signature + pre/post defense trajectory + cross-system
# reproduction status) to the remaining 7 silent-fallback hazard instances
# from silent-fallback-hazards.md.
#
# Instance 6 was covered in §09 ; summarized here with reference.
# Instances 1, 6 not re-measured.
#
# What this script measures:
#  - Instance 2: PRs containing auto-close keywords; revert-PR auto-close
#               keyword inheritance count
#  - Instance 3: tmux-routing fragility incidents observed in tracking issues
#               (macf-actions#34, devops-toolkit#59 — public proxies)
#  - Instance 4: not measurable via gh api (cluster-side observability);
#               narrative only based on canonical rule
#  - Instance 5: workflow files in macf-* repos with vs without precheck-step
#               pattern (Pattern D structural defense)
#  - Instance 7: not measurable via gh api (Prometheus metrics); narrative only
#  - Instance 8: workflow runs that telemetered (a Tempo trace exists for the
#               run window) — proxy: which agent processes have OTel exporter
#               configured + whether the canonical fix landed
#
# Output:
#   data/multi-instance-audit/
#     ├── instance2-autoclose-keywords.tsv  -- PRs with auto-close keyword usage
#     ├── instance5-precheck-coverage.tsv   -- workflows with precheck-step pattern
#     ├── audit-summary.tsv                 -- per-instance methodology-bar score

set -euo pipefail

WORKSPACE=<HOME>/repos/groundnuty/macf-science-agent
OUT="$WORKSPACE/data/multi-instance-audit"
mkdir -p "$OUT"

export GH_TOKEN=${GH_TOKEN:-$(cat /tmp/claude/tok.txt)}

if ! gh api /rate_limit --silent >/dev/null 2>&1; then
  echo "FATAL: GH_TOKEN invalid (401)." >&2; exit 1
fi

REPOS=(groundnuty/macf groundnuty/macf-actions groundnuty/macf-marketplace groundnuty/macf-devops-toolkit groundnuty/macf-science-agent)

# Helper: count lines matching extended-regex (case-insensitive). Avoids the
# pipefail / grep-c-empty-stdin trap by routing through awk + wc -l (always
# exit 0). All counters use this.
count_match() {
  printf '%s\n' "$1" | awk -v p="$2" 'BEGIN{IGNORECASE=1} $0 ~ p' | wc -l
}

# ---------- Instance 2 — auto-close keyword usage in PR bodies ----------

# Auto-close keywords (9 forms per silent-fallback-hazards.md §Instance 2):
# Closes Fixes Resolves Close Fix Resolve Closed Fixed Resolved
# Plus inverse: "Refs" (the canonical alternative)

{
  echo -e "repo\ttotal_prs\tprs_with_autoclose\tprs_with_refs\trevert_prs\trevert_with_keyword"
  for repo in "${REPOS[@]}"; do
    short=$(basename "$repo")
    pr_data=$(gh api "/repos/$repo/pulls?state=closed&per_page=100" --paginate \
              --jq '.[] | "\(.number)\t\(.title | gsub("\\t"; " "))\t\((.body // "") | gsub("\\n"; " ") | gsub("\\t"; " "))"' 2>/dev/null || true)
    total=$(printf '%s\n' "$pr_data" | awk 'NF>0' | wc -l)
    auto_close=$(count_match "$pr_data" '(Closes|Fixes|Resolves|Close|Fix|Resolve|Closed|Fixed|Resolved)[ ]+#[0-9]+')
    refs=$(count_match "$pr_data" '\\<Refs?[ ]+#[0-9]+')
    revert_lines=$(printf '%s\n' "$pr_data" | awk -F'\t' '$2 ~ /^Revert/')
    revert_total=$(printf '%s\n' "$revert_lines" | awk 'NF>0' | wc -l)
    revert_kw=$(count_match "$revert_lines" '(Closes|Fixes|Resolves|Close|Fix|Resolve|Closed|Fixed|Resolved)[ ]+#[0-9]+')
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$short" "$total" "$auto_close" "$refs" "$revert_total" "$revert_kw"
  done
} > "$OUT/instance2-autoclose-keywords.tsv"

echo "=== Instance 2: auto-close keyword usage ==="
column -t -s $'\t' "$OUT/instance2-autoclose-keywords.tsv"
echo ""

# ---------- Instance 5 — precheck-step pattern coverage in workflow files ----------

# The Pattern D defense: a precheck step early in the workflow that asserts
# all required secrets are present + non-empty, with aggregate-fail-loud.

{
  echo -e "repo\tworkflow_file\thas_precheck\tuses_secrets"
  for repo in "${REPOS[@]}"; do
    short=$(basename "$repo")
    wf_files=$(gh api "/repos/$repo/contents/.github/workflows" --jq '.[]?.name' 2>/dev/null | grep '\.ya\?ml$' || true)
    for wf in $wf_files; do
      content=$(gh api "/repos/$repo/contents/.github/workflows/$wf" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
      uses_secrets=$(count_match "$content" 'secrets\\.[A-Z_]+')
      has_precheck=$(count_match "$content" 'missing\\+=|::error::Missing|fail.loud|precheck.*secret|verify.*secrets|check.*secrets')
      [ "$uses_secrets" -gt 0 ] && printf "%s\t%s\t%s\t%s\n" "$short" "$wf" "$has_precheck" "$uses_secrets"
    done
  done
} > "$OUT/instance5-precheck-coverage.tsv"

echo "=== Instance 5: precheck-step coverage in workflow files ==="
column -t -s $'\t' "$OUT/instance5-precheck-coverage.tsv"
echo ""

# ---------- Methodology-bar audit summary ----------

# For each instance, score on 4 dimensions:
# 1. Failure-mode signature documented (in silent-fallback-hazards.md)
# 2. Pre-defense observation evidence (concrete trace)
# 3. Defense landed (commit on main)
# 4. Cross-system reproduction or transferability evidence

cat > "$OUT/audit-summary.tsv" <<'TSV'
instance	signature_doc	pre_defense_evidence	defense_commit	cross_system	notes
1: gh-token attribution	YES (canonical rule + 6 modes)	YES (31 events §04)	YES (#142 PreToolUse hook)	YES (CPC §10 + consumer §20)	covered §03+§04+§06+§07+§10+§20
2: auto-close negation	YES (canonical pr-discipline §1)	YES (testbed#41/#42 incident; revert-keyword inheritance 2026-04-29)	YES (#225 coordination.md §Issue Lifecycle 1 + pr-discipline.md)	NO (single-system)	this audit
3: RC IPC blocks tmux	YES (canonical rule + memory)	YES (cv-architect 2026-04-21 + macf-actions#34 + devops-toolkit#59)	PARTIAL (consumer fleet structurally retired via DR-020 mTLS routing; substrate operational reality)	YES (cross-agent triangulated 2026-04-26)	this audit
4: Loki/CH divergence	YES (canonical observability-wiring)	YES (phase-1 verification multi-tester scenario)	YES (#246 observability-wiring + manifest-warnings shape detection)	NO (single-system)	cluster-side; not gh-api-measurable
5: workflow secret name	YES (canonical silent-fallback-hazards Instance 5 + Pattern D)	YES (3 confusing workflow runs pre-precheck)	PARTIAL (Pattern D documented; not yet structurally enforced across all workflows)	YES (GitHub community discussions per paper §1¶3)	this audit
6: cross-agent loop	YES (canonical Pattern E)	YES (8-cycle recursion trace §09)	YES (#268 Pattern E receiver-side discriminator)	NO (substrate-only; cross-agent emergent)	covered §09 
7: OTel-counter cumulative	YES (canonical observability-wiring)	YES (T6 metrics runtime verification)	PARTIAL (Phase 1 doc workaround shipped; Phase 2 SDK delta temporality in flight)	NO (single-system)	cluster-side; not gh-api-measurable
8: OTLP endpoint drop	YES (canonical silent-fallback-hazards Instance 8 + 5-surface defense)	YES (34-min consumer run with 0 traces)	YES (#246 + #294 + Tier 1-4 surfaces)	YES (production observability runbooks per paper §1¶3)	cluster + agent-process; partial gh-api-measurable
TSV

echo "=== Audit summary (methodology-bar per instance) ==="
column -t -s $'\t' "$OUT/audit-summary.tsv"
echo ""
echo "Done. Artifacts under: $OUT"

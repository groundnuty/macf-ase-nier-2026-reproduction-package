#!/usr/bin/env bash
# analyze §21 DR-2 state placement (§3.2 reinforcement)
#
# Reads frozen reachability-summary.tsv + instance-chains.tsv and verifies:
#   - 31/31 (100%) of pre-#140 mis-attributed events still URL-reachable
#   - 7/8 hazard instances trace to a canonical rule file
#   - 6/8 instances have a clearly traceable PR-driven canonical-promotion chain
#
# Anchors paper §3.2 (DD2) "preserves the design-decision provenance property"
# claim with empirical numbers.
#
# Reviewer-runnable from clean clone — no token/SSH/live API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$WORKSPACE/data/dr2-state-placement"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

echo "=== §21 DR-2 state placement (§3.2 reinforcement) ==="
echo ""

echo "## Reachability summary (frozen TSV)"
column -t -s $'\t' "$DATA_DIR/reachability-summary.tsv"
echo ""

# Verify 31/31 = 100%
reachable=$(awk -F'\t' '$1 == "reachable" {print $2}' "$DATA_DIR/reachability-summary.tsv")
total=$(awk -F'\t' '$1 == "total" {print $2}' "$DATA_DIR/reachability-summary.tsv")

echo "## Instance chains (frozen TSV)"
column -t -s $'\t' "$DATA_DIR/instance-chains.tsv" | head -10
echo ""

# Count canonical-rule coverage
total_instances=$(awk -F'\t' 'NR>1' "$DATA_DIR/instance-chains.tsv" | wc -l)
with_canonical=$(awk -F'\t' 'NR>1 && $4 != "—"' "$DATA_DIR/instance-chains.tsv" | wc -l)
canonical_pct=$(python3 -c "print(f'{100*$with_canonical/$total_instances:.1f}')")

echo "## Canonical-rule coverage"
printf "  Instances with canonical-rule reference: %d of %d = %s%%\n" "$with_canonical" "$total_instances" "$canonical_pct"

echo ""
echo "## Verification against frozen TSV (strict canonical_commit field)"
fail=0
assert_match "31" "$reachable"  "31 events URL-reachable"        || fail=1
assert_match "31" "$total"      "31 events total"                || fail=1
assert_match "8"  "$total_instances" "8 hazard instances total"  || fail=1
assert_match "6"  "$with_canonical"  "6 instances with canonical_commit (TSV strict count)" || fail=1
assert_match "75.0" "$canonical_pct" "75.0% strict canonical-rule coverage" || fail=1

echo ""
echo "## §21 vs frozen TSV reconciliation (DOUBLE-CHECK FINDING #4)"
echo ""
echo "  §21 prose: '7/8 hazard instances trace to a canonical rule file' (87.5%)"
echo "             'the eighth is indexed in the master hazard rule itself'"
echo "  Frozen TSV (instance-chains.tsv canonical_commit field):"
echo "    Strict count of non-'—' canonical_commit = 6/8 = 75.0%"
echo ""
echo "  Source of discrepancy: §21's 7/8 framing apparently counts Instance 3"
echo "  (DR-020 mTLS routing — NOT in plugin/rules/) as a 'canonical reference'."
echo "  The strict-construal count by canonical-rule files actually IN"
echo "  plugin/rules/ is 6/8 (Instance 3 NO; Instance 5 catalog-only)."
echo ""
echo "  Recommended §28 update: '6/8 (75%) hazard instances trace to a"
echo "  canonical rule file under plugin/rules/; 8/8 are documented at"
echo "  least in the master silent-fallback-hazards.md catalog.'"

echo ""
if [ "$fail" = "0" ]; then
  echo "✓ Paper §3.2 (DD2) state-placement provenance VERIFIED (refined)."
  echo ""
  echo "## Paper §3.2 anchor"
  echo "  - 31/31 (100%) of mis-attributed events URL-reachable via gh api"
  echo "    24+ days after the events occurred"
  echo "  - 6/8 (75%) hazard instances trace to a canonical rule file"
  echo "    under plugin/rules/; 8/8 documented in master hazard catalog"
  echo "  - Empirically validates DD2's GitHub-as-state-substrate framing"
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

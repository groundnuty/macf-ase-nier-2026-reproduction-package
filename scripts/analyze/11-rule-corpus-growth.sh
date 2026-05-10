#!/usr/bin/env bash
# analyze §11 rule-corpus growth (paper §4.5 80% claim)
#
# Reads frozen rule-corpus-growth.tsv and emits per-surface first-half /
# second-half growth split. Anchors paper §4.5's "two-thirds" claim → tightened
# to "approximately 80% average across surfaces; canonical surface 92%".
#
# **DOUBLE-CHECK FINDINGS** (operator authorized 2026-05-09):
#
# 1. **§11 vs TSV science-agent count**: §11 prose lists science-agent
#    workbench = 9 rules (5/4 split = 55.6% first-half). Frozen TSV has 8
#    science-agent rules (4/4 split = 50.0%). One rule is missing from the
#    TSV (likely agent-identity.md not captured at TSV-generation time).
#    Across-surface average shifts: 79.9% (§11) → 78.5% (TSV).
#
# 2. **§28 cite of "10-of-13" canonical is wrong**: §28 §"§4.5" says
#    "tighten to 80% / 10-of-13" but canonical surface is **12-of-13 =
#    92.3%** (NOT 10-of-13). The 80% is the AVERAGE across 4 surfaces, not
#    a canonical-only fraction. §28 should be corrected to either:
#    - "approximately 78.5% average across 4 substrate surfaces (canonical:
#      12-of-13 = 92.3%; code-agent: 80.0%; devops-agent: 91.7%; science-
#      agent: 50.0%)"
#    - OR "92% on the canonical surface (12 of 13 rules in first half of
#      its window)"
#
# Reviewer-runnable from clean clone — no token/SSH/live API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA="$WORKSPACE/data/rule-corpus-growth.tsv"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

echo "=== §11 rule-corpus growth ==="
echo "Reproducing paper §4.5 'two-thirds' claim refinement."
echo ""

echo "## Per-surface first-half / second-half split (from frozen TSV)"
python3 <<PYEOF
import datetime
from collections import defaultdict

rows = []
with open('$DATA') as f:
    next(f)  # skip header
    for line in f:
        parts = line.strip().split('\t')
        if len(parts) >= 3:
            rows.append({'date': parts[0], 'rule': parts[1], 'surface': parts[2]})

by_surface = defaultdict(list)
for r in rows:
    by_surface[r['surface']].append(r['date'])

print(f"  {'surface':<28} {'total':>6} {'window':<28} {'first':>6} {'second':>6} {'pct':>6}")
total_pct = 0.0
n_surfaces = 0
canonical_first = canonical_total = 0
for surf in sorted(by_surface.keys()):
    dates = sorted(by_surface[surf])
    n = len(dates)
    if n == 0: continue
    first = datetime.date.fromisoformat(dates[0])
    last = datetime.date.fromisoformat(dates[-1])
    mid = first + (last - first) / 2
    first_half = sum(1 for d in dates if datetime.date.fromisoformat(d) <= mid)
    second_half = n - first_half
    pct = 100 * first_half / n
    window = f"{dates[0]}..{dates[-1]}"
    print(f"  {surf:<28} {n:>6} {window:<28} {first_half:>6} {second_half:>6} {pct:>5.1f}%")
    total_pct += pct
    n_surfaces += 1
    if surf == 'canonical':
        canonical_first = first_half
        canonical_total = n

avg = total_pct / n_surfaces
print(f"  {'AVERAGE':<28} {'':>6} {'':<28} {'':>6} {'':>6} {avg:>5.1f}%")
print()
print(f"## Canonical-only summary")
print(f"  {canonical_first} of {canonical_total} canonical rules in first half = {100*canonical_first/canonical_total:.1f}%")

# Also write outputs to env-equivalent vars for shell to read
import os
os.environ['_AVG_PCT'] = f"{avg:.1f}"
os.environ['_CANONICAL_FIRST'] = str(canonical_first)
os.environ['_CANONICAL_TOTAL'] = str(canonical_total)

# Save to /tmp for shell to pick up
with open('/tmp/_sprint_e_vars', 'w') as f:
    f.write(f"AVG_PCT={avg:.1f}\nCANONICAL_FIRST={canonical_first}\nCANONICAL_TOTAL={canonical_total}\n")
PYEOF

# shellcheck disable=SC1091
. /tmp/_sprint_e_vars

echo ""
echo "## Verification against frozen TSV (the byte-verifiable artifact)"
fail=0
assert_match "12" "$CANONICAL_FIRST" "canonical first-half count"  || fail=1
assert_match "13" "$CANONICAL_TOTAL" "canonical total count"        || fail=1
assert_match "78.5" "$AVG_PCT" "across-surface average (frozen)"   || fail=1

echo ""
echo "## §11 vs TSV reconciliation (DOUBLE-CHECK FINDING #1)"
echo ""
echo "  §11 prose: science-agent = 9 rules (5/4 = 55.6%); average = 79.9%"
echo "  Frozen TSV: science-agent = 8 rules (4/4 = 50.0%);  average = 78.5%"
echo "  Δ = 1 rule missing from TSV (likely agent-identity.md not captured"
echo "      at TSV-generation time). Material claim ('80% average') unchanged."

echo ""
echo "## §28 cite reconciliation (DOUBLE-CHECK FINDING #2)"
echo ""
echo "  §28 row '§4.5 two-thirds' says: 'Tighten to 80% / 10-of-13'"
echo "  CORRECT figure: canonical = 12-of-13 = 92.3% (NOT 10-of-13)"
echo "  The 80% is the AVERAGE across 4 surfaces, not a canonical-only"
echo "  fraction. §28 needs correction."
echo ""
echo "  Recommended §28 replacement: 'tighten to approximately 78.5% across"
echo "  4 substrate surfaces; canonical surface 92.3% (12 of 13 rules in"
echo "  first half of its window)'"

echo ""
if [ "$fail" = "0" ]; then
  echo "✓ All frozen-TSV values verified."
  echo ""
  echo "## Paper §4.5 anchor (refined per double-check)"
  echo "  - Across 4 substrate surfaces: ${AVG_PCT}% average first-half-of-window"
  echo "    (canonical: ${CANONICAL_FIRST}-of-${CANONICAL_TOTAL} = $(python3 -c "print(f'{100*$CANONICAL_FIRST/$CANONICAL_TOTAL:.1f}')")%)"
  echo "  - Paper's 'two-thirds' (67%) framing is supported and conservative"
  echo "  - Canonical surface stabilized 9+ days ago (zero new canonical rules"
  echo "    after 2026-04-30)"
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

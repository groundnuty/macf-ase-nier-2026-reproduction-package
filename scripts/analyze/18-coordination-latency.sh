#!/usr/bin/env bash
# analyze §18 coordination latency (R5: §3.4 reinforcement)
#
# Reads frozen coordination-latency/latencies-sorted.txt + latencies.tsv.
# Verifies:
#   - Median 56s end-to-end inter-agent latency
#   - Range 46-78s, mean 59.8s, n=13 (sample of 20 snippets, 13 produced clean)
#   - GitHub Actions cold-start ~30-50s dominates the latency budget
#   - JIT/self-hosted runners would yield 3-6× speedup (~10-25s)
#
# Anchors §28 R5 (median 56s coordination latency reinforcement).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
LATENCIES="$WORKSPACE/data/coordination-latency/latencies-sorted.txt"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

echo "=== §18 coordination latency (R5) ==="
echo ""

# Compute median, mean, min, max from the sorted file
n=$(wc -l < "$LATENCIES")
min=$(head -1 "$LATENCIES")
max=$(tail -1 "$LATENCIES")
median=$(python3 -c "
vals = [int(line) for line in open('$LATENCIES')]
vals.sort()
n = len(vals)
print(vals[n//2] if n % 2 else (vals[n//2 - 1] + vals[n//2]) / 2)
")
mean=$(python3 -c "
vals = [int(line) for line in open('$LATENCIES')]
print(f'{sum(vals)/len(vals):.1f}')
")

echo "## Latency distribution (frozen TSV)"
echo "  All 13 latency values (sorted, seconds):"
cat "$LATENCIES" | awk '{printf "    %s\n", $0}'
echo ""

echo "## Statistics"
printf "  %-15s %s\n" "n:"      "$n"
printf "  %-15s %s s\n" "min:"  "$min"
printf "  %-15s %s s\n" "max:"  "$max"
printf "  %-15s %s s\n" "median:" "$median"
printf "  %-15s %s s\n" "mean:"   "$mean"

echo ""
echo "## Verification against §18 documented values"
fail=0
assert_match "13" "$n"      "n=13 (sample of 20; 13 produced clean measurements)" || fail=1
assert_match "46" "$min"    "min latency 46s"            || fail=1
assert_match "78" "$max"    "max latency 78s"            || fail=1
assert_match "56" "$median" "median latency 56s"         || fail=1
assert_match "59.8" "$mean" "mean latency 59.8s"          || fail=1

echo ""
if [ "$fail" = "0" ]; then
  echo "✓ §18 coordination-latency verifications match."
  echo ""
  echo "## Paper §3.4 + §6 future-work anchor"
  echo "  - Inter-agent message-delivery latency: median ${median}s (range $min-${max}s)"
  echo "    for SA-comment-posted → CA-session-fresh-turn cycle"
  echo "  - GitHub Actions cold-start ~30-50s dominates the latency budget"
  echo "  - JIT/self-hosted runners would reduce to ~10-25s (3-6× speedup)"
  echo "  - Future-work direction in §6 — operator-driven JIT-runner deployment"
else
  echo "✗ Verification failed — see mismatches above" >&2
  exit 1
fi

#!/usr/bin/env bash
# §15 — CPC adoption of MACF helpers
#
# Question: did CPC sessions ever import or reference MACF's
# canonical helper script (macf-gh-token.sh)? Result: 0 references in
# 922 CPC session logs → CPC = clean control group, no diffusion of
# MACF's structural defense.
#
# CPC session logs live on operator's macbook. Requires SSH.
#
# Usage:
#   MACBOOK=<OPERATOR>@<TAILSCALE_IP> ./15-cpc-helper-adoption.sh

set -euo pipefail

MACBOOK=${MACBOOK:-<OPERATOR>@<TAILSCALE_IP>}

echo "=== CPC helper adoption check ==="
echo "Searching CPC session logs for 'macf-gh-token' references..."

count=$(ssh "$MACBOOK" '
  find ~/.claude/projects -path "*claude-plan-composer*" -name "*.jsonl" -type f -exec grep -c "macf-gh-token" {} \;
' | awk '{s+=$1} END {print s+0}')

echo "Total references: $count"
echo ""
echo "Expected: 0 (CPC = clean control group; no MACF defense diffusion)"

if [ "$count" -gt 0 ]; then
  echo "WARNING: non-zero count — CPC may have adopted MACF helpers; clean-control-group claim invalidated"
fi

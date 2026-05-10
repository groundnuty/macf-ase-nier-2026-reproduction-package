#!/usr/bin/env bash
# §20 — consumer fleet attribution check
#
# Verifies whether `macf init` actually deployed the structural defense
# stack (helper + hook + settings.json wiring + canonical rules + .macf
# workspace + macf-agent.json) on consumer workspaces (CV agents,
# PPAM agents, future macf-init'd agents).
#
# Then samples session logs for hook-fire markers ("BLOCKED by MACF
# attribution-trap"). Result: 8 REAL autonomous hook fires across the
# 14-day PPAM window vs 0 in substrate.
#
# Consumer workspaces live on operator's macbook. Requires SSH.
#
# Usage:
#   MACBOOK=<OPERATOR>@<TAILSCALE_IP> ./20-consumer-fleet-attribution.sh
#
# Output: stdout summary; no persistent data dir (live SSH queries).
# To persist, run with `tee data/consumer-fleet/snapshot.txt`.

set -euo pipefail

MACBOOK=${MACBOOK:-<OPERATOR>@<TAILSCALE_IP>}

# Known consumer workspaces (academic-cv + ppam-2026 + cyfronet-llm-forge)
WORKSPACES=(
  "<HOME>/repos/groundnuty/academic-resume"
  "<HOME>/repos/groundnuty/cv-project-archaeologist"
  "<HOME>/repos/papers/ppam-2026"
  "<HOME>/repos/groundnuty/claude-code-cyfronet-llm-forge"
)

ssh "$MACBOOK" "
  set -e
  echo '=== Consumer workspace deployment status ==='
  printf '%-60s | %-6s | %-4s | %-7s | %-3s | %-6s | %s\n' \
    'Workspace' 'helper' 'hook' 'settings' 'rules' '.macf/' 'agent.json'
  echo '----'
  for ws in ${WORKSPACES[@]}; do
    helper=\$([ -f \"\$ws/.claude/scripts/macf-gh-token.sh\" ] && echo Y || echo N)
    hook=\$([ -f \"\$ws/.claude/scripts/check-gh-token.sh\" ] && echo Y || echo N)
    settings=\$(grep -l 'check-gh-token' \"\$ws/.claude/settings.json\" 2>/dev/null && echo Y || echo N)
    rules=\$(ls \"\$ws/.claude/rules/\"*.md 2>/dev/null | wc -l | tr -d ' ')
    macfdir=\$([ -d \"\$ws/.macf\" ] && echo Y || echo N)
    agentjson=\$([ -f \"\$ws/.macf/macf-agent.json\" ] && echo Y || echo N)
    printf '%-60s | %-6s | %-4s | %-7s | %-3s | %-6s | %s\n' \
      \"\$ws\" \"\$helper\" \"\$hook\" \"\$settings\" \"\$rules\" \"\$macfdir\" \"\$agentjson\"
  done

  echo ''
  echo '=== Hook-fire markers (BLOCKED by MACF attribution-trap) per workspace ==='
  for ws in ${WORKSPACES[@]}; do
    short=\$(basename \"\$ws\")
    encoded=\$(echo \"\$ws\" | sed 's|/|-|g; s|^-||')
    log_dir=\"\$HOME/.claude/projects/\$encoded\"
    fires=\$(grep -rh 'BLOCKED by MACF attribution-trap' \"\$log_dir\" 2>/dev/null | wc -l | tr -d ' ')
    printf '%-50s : %s hook-fires\n' \"\$short\" \"\$fires\"
  done
"

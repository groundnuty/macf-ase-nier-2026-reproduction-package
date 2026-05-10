#!/usr/bin/env bash
# §12 — bfa64ae4 outlier investigation
#
# Context: §07 trajectory analysis surfaced a 2026-04-17 spike. Drill-in
# attributes the spike to ONE session log (bfa64ae4-*.jsonl on macbook,
# poster paper-writing session) where the bulk of "events" are
# attachment-type messages with check-gh-token references — NOT real
# Bash/Edit/Write tool_use invocations with hook activity. False
# positive — does not represent post-#140 reversal.
#
# The bfa64ae4 file lives only on operator's macbook + is too large to
# copy. Reproduction requires SSH to the macbook.
#
# Usage:
#   MACBOOK=<OPERATOR>@<TAILSCALE_IP> ./12-bfa64ae4-outlier.sh
#
# Output: stdout summary; no persistent artifacts (the source file is
# remote-only).

set -euo pipefail

MACBOOK=${MACBOOK:-<OPERATOR>@<TAILSCALE_IP>}
LOG_PATTERN='<HOME>/.claude/projects/*/bfa64ae4-*.jsonl'

ssh "$MACBOOK" "
  set -e
  LOG=\$(ls $LOG_PATTERN 2>/dev/null | head -1)
  [ -z \"\$LOG\" ] && { echo 'bfa64ae4 file not found' >&2; exit 1; }
  echo \"=== bfa64ae4 outlier investigation ===\"
  echo \"Log: \$LOG\"
  echo \"\"
  echo \"Total events on 2026-04-17: \$(jq -c 'select(.timestamp[:10] == \"2026-04-17\")' \"\$LOG\" | wc -l)\"
  echo \"Of which attachment-type (false-positive markers): \$(jq -c 'select(.timestamp[:10] == \"2026-04-17\" and (.message?.content // [] | tostring | contains(\"check-gh-token\")))' \"\$LOG\" | wc -l)\"
  echo \"Of which REAL tool_use Bash/Edit/Write events with hook activity: \$(jq -c 'select(.timestamp[:10] == \"2026-04-17\" and .message?.content?[0]?.type == \"tool_use\" and ([\"Bash\",\"Edit\",\"Write\"] | index(.message.content[0].name)) != null)' \"\$LOG\" | wc -l)\"
"

# Expected:
# Total events on 2026-04-17: 7333
# Of which attachment-type (false-positive markers): ~1831
# Of which REAL tool_use Bash/Edit/Write events with hook activity: ~0

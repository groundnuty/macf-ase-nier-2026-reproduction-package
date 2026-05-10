#!/usr/bin/env bash
# Refresh the science-agent bot installation token via the canonical
# fail-loud helper. Cache to /tmp/claude/tok.txt (chmod 600).
#
# Usage:
#   ./01-refresh-token.sh
#
# Output: prints token to stdout. Caller exports as GH_TOKEN.
# Side-effect: writes /tmp/claude/tok.txt with mode 0600 for reuse.
#
# Per substrate-drift pattern (see ~/.claude/.../memory/feedback_token_file_cache_pattern.md):
# the file-cache is the substrate workaround for Bash-tool non-persistence.
# Different from canonical inline-chain pattern.

set -euo pipefail

WORKSPACE="<HOME>/repos/groundnuty/macf-science-agent"
APP_ID="<APP_ID>"
INSTALL_ID="<INSTALL_ID>"
KEY_PATH="${WORKSPACE}/.github-app-key.pem"

mkdir -p /tmp/claude
TOKEN_FILE=/tmp/claude/tok.txt

cd "$WORKSPACE" && MACF_SKIP_TOKEN_CHECK=1 \
  ./.claude/scripts/macf-gh-token.sh \
    --app-id "$APP_ID" \
    --install-id "$INSTALL_ID" \
    --key "$KEY_PATH" > "$TOKEN_FILE" 2>&1

chmod 600 "$TOKEN_FILE"

# Verify it has the ghs_ prefix (fail-loud per attribution-trap discipline)
TOKEN=$(cat "$TOKEN_FILE")
if [[ "$TOKEN" != ghs_* ]]; then
  echo "FATAL: token mint did not produce a ghs_ token. Got: ${TOKEN:0:10}..." >&2
  exit 1
fi

cat "$TOKEN_FILE"

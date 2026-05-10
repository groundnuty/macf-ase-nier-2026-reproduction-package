#!/usr/bin/env bash
# §4.4 Pattern E — helper to spawn an isolated macf-channel-server test
# instance with self-signed test certs + ephemeral port + a per-trial
# tmux session as the wake target.
#
# Reads env (caller exports them):
#   TRIAL_DIR             — workdir for this trial (certs, registry,
#                           workspace, log file go here; caller mkdir's)
#   TRIAL_TMUX_SESSION    — tmux session name to wire as wake target
#                           (caller creates the session BEFORE invoking)
#   CHANNEL_SERVER_BIN    — path to the channel-server entrypoint JS
#                           (e.g. /.../macf-channel-server/dist/server.js)
#   TMUX_HELPER_SRC       — path to the canonical tmux-send-to-claude.sh
#                           in the macf source tree; we copy it into
#                           TRIAL_DIR/.claude/scripts/ so wakeViaTmux's
#                           helper-existence check passes
#
# Writes:
#   $TRIAL_DIR/server.log   — JSON log lines from channel-server
#   $TRIAL_DIR/server.stderr — stderr (debug + fatal)
#   stdout: <pid> <port>     — the spawned PID and ephemeral port the
#                              kernel chose (parsed from server_started
#                              JSON log line)
#
# Idempotent: caller's responsibility to clean up; this helper just
# waits until either `server_started` lands or 10s elapses.
#
# Pre-reg: appendix/A5-failure-injection.md §"Pattern E"

set -euo pipefail

: "${TRIAL_DIR:?TRIAL_DIR required}"
: "${TRIAL_TMUX_SESSION:?TRIAL_TMUX_SESSION required}"
: "${CHANNEL_SERVER_BIN:?CHANNEL_SERVER_BIN required}"
: "${TMUX_HELPER_SRC:?TMUX_HELPER_SRC required}"

CERTS_DIR="$TRIAL_DIR/certs"
REGISTRY_DIR="$TRIAL_DIR/registry"
REGISTRY_FILE="$REGISTRY_DIR/test.json"
WS_DIR="$TRIAL_DIR/workspace"
HELPER_DIR="$WS_DIR/.claude/scripts"
LOG_PATH="$TRIAL_DIR/server.log"
STDERR_PATH="$TRIAL_DIR/server.stderr"

mkdir -p "$CERTS_DIR" "$REGISTRY_DIR" "$HELPER_DIR"

# DR-024 trust-boundary perms for local-mode registry (parent dir 0700).
chmod 700 "$REGISTRY_DIR"

# Copy canonical helper into the synthetic workspace so wakeViaTmux's
# existsSync(...) check passes for negative-control trials.
cp "$TMUX_HELPER_SRC" "$HELPER_DIR/tmux-send-to-claude.sh"
chmod +x "$HELPER_DIR/tmux-send-to-claude.sh"

# --- Generate self-signed test CA + agent cert (modeled on
#     macf-channel-server/test/e2e/fixtures/gen-certs.ts).
CA_CERT="$CERTS_DIR/ca-cert.pem"
CA_KEY="$CERTS_DIR/ca-key.pem"
AGENT_CERT="$CERTS_DIR/agent-cert.pem"
AGENT_KEY="$CERTS_DIR/agent-key.pem"
AGENT_CSR="$CERTS_DIR/agent.csr"
AGENT_EXT="$CERTS_DIR/agent-ext.cnf"

openssl genrsa -out "$CA_KEY" 2048 >/dev/null 2>&1
openssl req -x509 -new -key "$CA_KEY" -out "$CA_CERT" \
  -days 1 -subj '/CN=test-ca' >/dev/null 2>&1

cat > "$AGENT_EXT" <<'EOF'
subjectAltName=IP:127.0.0.1,DNS:localhost
extendedKeyUsage=clientAuth,serverAuth
EOF

openssl genrsa -out "$AGENT_KEY" 2048 >/dev/null 2>&1
openssl req -new -key "$AGENT_KEY" -out "$AGENT_CSR" \
  -subj '/CN=injection-tester' >/dev/null 2>&1
openssl x509 -req -in "$AGENT_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" \
  -CAcreateserial -out "$AGENT_CERT" -days 1 \
  -extfile "$AGENT_EXT" >/dev/null 2>&1

# --- Spawn channel-server with test env. MACF_PORT=0 → kernel-chosen.
# MACF_REGISTRY_TYPE=local → no GitHub App needed (DR-024).
# MACF_DEBUG=true → also writes to stderr for live diagnosis.

# Run in a subshell so env-set is local; redirect logs; record PID.
(
  exec env \
    MACF_AGENT_NAME=injection-tester \
    MACF_AGENT_TYPE=permanent \
    MACF_PROJECT=paper-injection-e \
    MACF_HOST=127.0.0.1 \
    MACF_ADVERTISE_HOST=127.0.0.1 \
    MACF_PORT=0 \
    MACF_CA_CERT="$CA_CERT" \
    MACF_CA_KEY="$CA_KEY" \
    MACF_AGENT_CERT="$AGENT_CERT" \
    MACF_AGENT_KEY="$AGENT_KEY" \
    MACF_REGISTRY_TYPE=local \
    MACF_REGISTRY_PATH="$REGISTRY_FILE" \
    MACF_WORKSPACE_DIR="$WS_DIR" \
    MACF_TMUX_SESSION="$TRIAL_TMUX_SESSION" \
    MACF_LOG_PATH="$LOG_PATH" \
    MACF_DEBUG=false \
    node "$CHANNEL_SERVER_BIN"
) >/dev/null 2>"$STDERR_PATH" &
SERVER_PID=$!

# Wait up to 10s for `server_started` log line.
PORT=""
for _ in $(seq 1 100); do
  if [ -s "$LOG_PATH" ]; then
    PORT=$(grep -m1 '"event":"server_started"' "$LOG_PATH" 2>/dev/null \
      | sed -E 's/.*"port":([0-9]+).*/\1/' || true)
    if [ -n "$PORT" ] && [ "$PORT" != "0" ]; then break; fi
  fi
  # Fail fast if server died before listening
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "ERR: server died before server_started; stderr tail:" >&2
    tail -20 "$STDERR_PATH" >&2 || true
    exit 1
  fi
  sleep 0.1
done

if [ -z "$PORT" ] || [ "$PORT" = "0" ]; then
  echo "ERR: timed out waiting for server_started" >&2
  kill -TERM "$SERVER_PID" 2>/dev/null || true
  exit 1
fi

printf '%d %d\n' "$SERVER_PID" "$PORT"

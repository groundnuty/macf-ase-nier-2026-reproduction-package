#!/usr/bin/env bash
# §4.4 Pattern E — Type Discriminator at the Receiver (TD)
#
# Defense being tested: macf-channel-server's `notify` receiver-side
# wake-policy discriminator (`packages/macf-channel-server/src/wake-decision.ts`,
# `decideWake()`). Per silent-fallback-hazards.md §"Pattern E" + post-#355
# simplification:
#
#   peer_notification with event ∈ {session-end, turn-complete, error}
#     → SKIP tmux wake  (Pattern E loop-prevention)
#   peer_notification with event === 'custom'
#     → WAKE  (operator-driven slash-command path)
#   any other NotifyType (issue_routed, mention, ci_completion,
#     pr_review_state, startup_check)
#     → WAKE  (existing always-wake behaviour)
#
# Pre-reg: appendix/A5-failure-injection.md §"Pattern E"
# Pre-reg commit: 25c08da on branch feat/paper-attribution-validation.
#
# Trial layout (N=25):
#   Trials 1..20 — POSITIVE: peer_notification + event=session-end.
#                  Expected: tmux_wake_skipped log + window_activity unchanged.
#   Trials 21..25 — NEGATIVE-CONTROL: issue_routed.
#                  Expected: tmux_wake_delivered log + window_activity advanced.
#
# Per-trial:
#   1. mkdir an isolated TRIAL_DIR (certs / registry / synthetic workspace
#      / log file all live inside).
#   2. Create the per-trial tmux session BEFORE spawning channel-server
#      (the wake-target must exist when wakeViaTmux fires).
#   3. Spawn channel-server (spawn-test-server.sh) — picks ephemeral port,
#      waits for `server_started` log line, prints "<pid> <port>".
#   4. POST the test payload via curl with mTLS client cert.
#   5. Sleep 3s for log + wake to settle (tmux helper sleeps 1s between
#      Enter presses, plus IPC + log flush headroom).
#   6. Assert:
#        positive: tmux_wake_skipped + reason=peer_notification_autonomous_event
#                  + window_activity unchanged
#        negative: tmux_wake_delivered + window_activity advanced
#   7. Tear down: kill channel-server (TERM then KILL), tmux kill-session,
#      rm -rf TRIAL_DIR.
#
# Cleanup is non-negotiable: trap on EXIT records every spawned PID and
# every created tmux session and reaps both — even on error. Final
# verification step runs `pgrep + tmux list-sessions` and reports.
#
# Methodology deviation note (vs pre-reg wording — see
# data/failure-injection/methodology-deviations.md §Pattern E):
#   * Pre-reg's `session_activity` doesn't advance for detached tmux sessions
#     running non-TUI processes. We use `window_activity` instead — same
#     "pane was woken" semantic, actually responsive to send-keys output.
#     Both timestamps are recorded in trials.tsv for audit.
#   * Pre-reg references log key `action_path_skipped`; live (post-#355)
#     implementation logs `tmux_wake_skipped` with
#     reason=peer_notification_autonomous_event. We assert on the live
#     keys; the wake-vs-skip behavior under test is unchanged.
#
# Usage:
#   ./run.sh
#
# Output:
#   data/failure-injection/e/trials.tsv
#   data/failure-injection/firing-counts.tsv (append row E)
#   data/failure-injection/methodology-deviations.md (append §E)

set -euo pipefail

# --- Path setup -------------------------------------------------------------
WORKSPACE=<HOME>/repos/groundnuty/macf-science-agent
SCRIPT_DIR="$WORKSPACE/scripts/26-injection/e"
OUT_DIR="$WORKSPACE/data/failure-injection/e"
mkdir -p "$OUT_DIR"

TRIALS_TSV="$OUT_DIR/trials.tsv"
FIRING_TSV="$WORKSPACE/data/failure-injection/firing-counts.tsv"
DEVIATIONS_MD="$WORKSPACE/data/failure-injection/methodology-deviations.md"

CHANNEL_SERVER_BIN=<HOME>/repos/groundnuty/macf/packages/macf-channel-server/dist/server.js
TMUX_HELPER_SRC=<HOME>/repos/groundnuty/macf/packages/macf/scripts/tmux-send-to-claude.sh

if [ ! -f "$CHANNEL_SERVER_BIN" ]; then
  echo "FATAL: channel-server bin not built at $CHANNEL_SERVER_BIN" >&2
  echo "Build with: cd $(dirname $(dirname $CHANNEL_SERVER_BIN)) && npm run build" >&2
  exit 1
fi
if [ ! -f "$TMUX_HELPER_SRC" ]; then
  echo "FATAL: tmux helper missing at $TMUX_HELPER_SRC" >&2
  exit 1
fi
export CHANNEL_SERVER_BIN TMUX_HELPER_SRC

# --- Cleanup tracking -------------------------------------------------------
# Track spawned PIDs and created tmux sessions for the trap. Bash arrays.
declare -a SPAWNED_PIDS=()
declare -a SPAWNED_SESSIONS=()
declare -a SPAWNED_DIRS=()

cleanup_all() {
  local rc=$?
  set +e
  for pid in "${SPAWNED_PIDS[@]}"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  # Brief grace; then KILL stragglers
  sleep 0.3
  for pid in "${SPAWNED_PIDS[@]}"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  done
  for sess in "${SPAWNED_SESSIONS[@]}"; do
    [ -n "$sess" ] && tmux kill-session -t "$sess" 2>/dev/null || true
  done
  for d in "${SPAWNED_DIRS[@]}"; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
  return $rc
}
trap cleanup_all EXIT

# --- TSV headers ------------------------------------------------------------
printf "trial_n\tnotify_type\toutcome\tmcp_pushed\twake_skipped\tduration_ms\tdetails\n" > "$TRIALS_TSV"

if [ ! -s "$FIRING_TSV" ]; then
  printf "pattern\tK\tN\trate\twilson_95_lower\tnotes\n" > "$FIRING_TSV"
fi

# --- Trial runner -----------------------------------------------------------
N_POSITIVE=20
N_NEGATIVE=5
N_TOTAL=$((N_POSITIVE + N_NEGATIVE))
K=0

run_trial() {
  local trial_n="$1" subcat="$2"   # subcat = positive | negative
  local start_ms end_ms dur_ms outcome details mcp_pushed wake_skipped
  local trial_dir tmux_sess pid port http_code
  local notify_type payload
  local pre_act post_act pre_wact post_wact

  start_ms=$(date +%s%3N)

  trial_dir=$(mktemp -d -p "${TMPDIR:-/tmp}" "macf-pattern-e-trial-${trial_n}.XXXXXX")
  SPAWNED_DIRS+=("$trial_dir")

  tmux_sess="macf-pattern-e-trial-${trial_n}-$$"
  # Wake target is a `cat` process — consumes stdin, echoes back, so
  # window_activity advances when send-keys lands. Detached.
  tmux new-session -d -s "$tmux_sess" 'cat'
  SPAWNED_SESSIONS+=("$tmux_sess")
  sleep 0.2

  # Spawn channel-server
  export TRIAL_DIR="$trial_dir" TRIAL_TMUX_SESSION="$tmux_sess"
  local spawn_out
  if ! spawn_out=$("$SCRIPT_DIR/spawn-test-server.sh" 2>"$trial_dir/spawn.err"); then
    outcome="ERR_SPAWN"
    details="spawn-test-server.sh failed: $(tail -3 "$trial_dir/spawn.err" 2>/dev/null | tr '\n' ';' | head -c 200)"
    mcp_pushed="-"; wake_skipped="-"
    notify_type="-"
    end_ms=$(date +%s%3N); dur_ms=$((end_ms - start_ms))
    printf "%d\t%s\t%s\t%s\t%s\t%d\t%s\n" \
      "$trial_n" "$notify_type" "$outcome" "$mcp_pushed" "$wake_skipped" \
      "$dur_ms" "$details" >> "$TRIALS_TSV"
    return
  fi
  pid=$(echo "$spawn_out" | awk '{print $1}')
  port=$(echo "$spawn_out" | awk '{print $2}')
  SPAWNED_PIDS+=("$pid")

  # Capture pre-activity timestamps
  pre_act=$(tmux display -p -t "$tmux_sess" '#{session_activity}' 2>/dev/null || echo "0")
  pre_wact=$(tmux display -p -t "$tmux_sess" '#{window_activity}' 2>/dev/null || echo "0")

  # Build payload by subcat
  if [ "$subcat" = "positive" ]; then
    notify_type="peer_notification"
    payload=$(printf '{"type":"peer_notification","source":"test-source","event":"session-end","message":"trial %d"}' "$trial_n")
  else
    notify_type="issue_routed"
    payload=$(printf '{"type":"issue_routed","issue_number":42,"title":"trial %d"}' "$trial_n")
  fi

  # POST with mTLS client cert
  http_code=$(curl -k -sS \
    --cert "$trial_dir/certs/agent-cert.pem" \
    --key  "$trial_dir/certs/agent-key.pem" \
    --cacert "$trial_dir/certs/ca-cert.pem" \
    --resolve "localhost:$port:127.0.0.1" \
    -X POST "https://localhost:$port/notify" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    -o "$trial_dir/curl.body" \
    -w "%{http_code}" 2>"$trial_dir/curl.err" || echo "000")

  # Wait for log + wake to settle. Helper sleeps 1s between Enters; give
  # 3s headroom for IPC and log flush.
  sleep 3

  # Capture post-activity timestamps
  post_act=$(tmux display -p -t "$tmux_sess" '#{session_activity}' 2>/dev/null || echo "0")
  post_wact=$(tmux display -p -t "$tmux_sess" '#{window_activity}' 2>/dev/null || echo "0")

  # Inspect log
  local log="$trial_dir/server.log"
  local got_mcp_pushed=false got_wake_skipped=false got_wake_delivered=false
  local got_reason=""
  if grep -q '"event":"mcp_pushed"' "$log"; then got_mcp_pushed=true; fi
  if grep -q '"event":"tmux_wake_skipped"' "$log"; then
    got_wake_skipped=true
    got_reason=$(grep -o '"reason":"peer_notification_autonomous_event"' "$log" | head -1)
  fi
  if grep -q '"event":"tmux_wake_delivered"' "$log"; then got_wake_delivered=true; fi

  # mcp_pushed flag: HTTP 200 means /notify accepted; the discriminator
  # only affects wake. The MCP push occurred unless mcp_pushed log absent.
  if [ "$http_code" = "200" ] && [ "$got_mcp_pushed" = "true" ]; then
    mcp_pushed=true
  else
    mcp_pushed=false
  fi
  wake_skipped="$got_wake_skipped"

  # Outcome verdict
  if [ "$subcat" = "positive" ]; then
    # Pass: HTTP 200 + mcp_pushed + tmux_wake_skipped + reason matches
    #       + window_activity unchanged
    if [ "$http_code" = "200" ] \
       && [ "$got_mcp_pushed" = "true" ] \
       && [ "$got_wake_skipped" = "true" ] \
       && [ -n "$got_reason" ] \
       && [ "$post_wact" = "$pre_wact" ] \
       && [ "$got_wake_delivered" = "false" ]; then
      outcome="PASS"
      details="positive: skipped wake; reason=peer_notification_autonomous_event; pre_wact=$pre_wact post_wact=$post_wact pre_sact=$pre_act post_sact=$post_act"
      K=$((K+1))
    else
      outcome="FAIL"
      details="positive: http=$http_code mcp_pushed=$got_mcp_pushed wake_skipped=$got_wake_skipped wake_delivered=$got_wake_delivered reason='$got_reason' pre_wact=$pre_wact post_wact=$post_wact"
    fi
  else
    # Negative: HTTP 200 + mcp_pushed + tmux_wake_delivered + window_activity advanced
    if [ "$http_code" = "200" ] \
       && [ "$got_mcp_pushed" = "true" ] \
       && [ "$got_wake_delivered" = "true" ] \
       && [ "$got_wake_skipped" = "false" ] \
       && [ "$post_wact" -gt "$pre_wact" ]; then
      outcome="PASS"
      details="negative: woke as expected; pre_wact=$pre_wact post_wact=$post_wact pre_sact=$pre_act post_sact=$post_act"
      K=$((K+1))
    else
      outcome="FAIL"
      details="negative: http=$http_code mcp_pushed=$got_mcp_pushed wake_delivered=$got_wake_delivered wake_skipped=$got_wake_skipped pre_wact=$pre_wact post_wact=$post_wact"
    fi
  fi

  # Tear down this trial's server + session + dir
  kill -TERM "$pid" 2>/dev/null || true
  sleep 0.2
  kill -9 "$pid" 2>/dev/null || true
  tmux kill-session -t "$tmux_sess" 2>/dev/null || true
  rm -rf "$trial_dir"

  end_ms=$(date +%s%3N); dur_ms=$((end_ms - start_ms))
  printf "%d\t%s\t%s\t%s\t%s\t%d\t%s\n" \
    "$trial_n" "$notify_type" "$outcome" "$mcp_pushed" "$wake_skipped" \
    "$dur_ms" "$details" >> "$TRIALS_TSV"
}

# --- Run trials -------------------------------------------------------------
echo "=== Pattern E (TD) failure-injection — N=$N_TOTAL trials ==="
echo "    positive (peer_notification → skip): $N_POSITIVE"
echo "    negative (issue_routed → wake):      $N_NEGATIVE"
echo "Pre-reg: appendix/A5-failure-injection.md §Pattern E"
echo "Channel-server bin: $CHANNEL_SERVER_BIN"
echo ""

# Positive trials 1..N_POSITIVE
for i in $(seq 1 $N_POSITIVE); do
  run_trial "$i" "positive"
  printf "."
done
echo " positive done"

# Negative-control trials N_POSITIVE+1 .. N_TOTAL
for i in $(seq $((N_POSITIVE+1)) $N_TOTAL); do
  run_trial "$i" "negative"
  printf "n"
done
echo " negative done"

# --- Aggregate --------------------------------------------------------------
WILSON=$(python3 -c "
import math
K, N = $K, $N_TOTAL
if N == 0: print('—'); exit()
z = 1.96
p = K/N
center = (p + z*z/(2*N)) / (1 + z*z/N)
margin = z * math.sqrt(p*(1-p)/N + z*z/(4*N*N)) / (1 + z*z/N)
lower = max(0.0, center - margin)
print(f'{lower*100:.1f}')
")
RATE=$(python3 -c "print(f'{100*$K/$N_TOTAL:.1f}')")

# Append (idempotent: replace existing pattern=E row if present)
grep -v '^E\b' "$FIRING_TSV" > "$FIRING_TSV.tmp" || true
mv "$FIRING_TSV.tmp" "$FIRING_TSV"
printf "E\t%d\t%d\t%s%%\t%s%%\ttype-discriminator at receiver (post-#355 decideWake); 20 positive (peer_notification→skip) + 5 negative-control (issue_routed→wake)\n" \
  "$K" "$N_TOTAL" "$RATE" "$WILSON" >> "$FIRING_TSV"

# --- Append methodology-deviations §Pattern E -------------------------------
if [ ! -f "$DEVIATIONS_MD" ]; then
  printf '# §4.4 Failure-injection — methodology deviations from pre-reg\n\nDocumented deviations from `26-failure-injection-pre-reg.md`, with rationale.\n\n' > "$DEVIATIONS_MD"
fi

# Idempotent: if §Pattern E section already there, replace; else append.
if grep -q '^## Pattern E$' "$DEVIATIONS_MD"; then
  python3 - "$DEVIATIONS_MD" <<'PY'
import sys, re
p = sys.argv[1]
with open(p) as f: text = f.read()
# Remove existing §Pattern E section (from "## Pattern E" until next "## " or EOF)
text = re.sub(r'(?ms)^## Pattern E$.*?(?=^## |\Z)', '', text)
with open(p, 'w') as f: f.write(text.rstrip() + '\n')
PY
fi

cat >> "$DEVIATIONS_MD" <<EOF

## Pattern E

Pre-reg §"Pattern E" (commit 25c08da) specifies two assertions: (a) MCP
push delivered, (b) tmux pane was not woken (pre/post \`session_activity\`
check), and references a log key \`action_path_skipped\` "or equivalent".
Two reconciliations against the live (post-#355) implementation:

1. **Log key name.** The live channel-server logs
   \`tmux_wake_skipped\` with \`reason=peer_notification_autonomous_event\`
   for the Pattern E branch (\`packages/macf-channel-server/src/server.ts\`
   line 160). The pre-reg's "or equivalent" qualifier covers this — the
   harness asserts on the live keys. The wake-vs-skip behaviour under
   test is unchanged; only the log-event spelling differs from the
   pre-reg's draft wording. The post-#355 simplification (macf v0.2.21)
   replaced a sender-side \`wake?: boolean\` field with a receiver-side
   \`event === 'custom'\` discriminator; the architecturally-load-bearing
   property — peer_notification-with-autonomous-event → skip wake — is
   preserved.

2. **Activity timestamp choice.** Pre-reg recommends comparing
   \`session_activity\` pre/post curl. Empirically, \`session_activity\`
   advances only when an attached tmux client interacts; in the
   harness's detached test sessions (running \`cat\` as the wake target)
   it remains constant on BOTH positive and negative trials, which would
   make it useless as a discriminator. We additionally record
   \`window_activity\`, which advances on send-keys-driven pane output
   (verified manually: idle = unchanged; \`cat\` echoing send-keys input
   = advanced). Both timestamps appear in trials.tsv as
   \`pre_sact\`/\`post_sact\` and \`pre_wact\`/\`post_wact\`. The PASS
   criterion uses \`window_activity\` as the load-bearing observable;
   \`session_activity\` is recorded for audit. The log-event assertion
   (\`tmux_wake_skipped\` vs \`tmux_wake_delivered\`) is the primary
   defense-firing observable; activity-timestamp is corroborating.

3. **N=25, not N=20.** Pre-reg specifies N=20 for §4.4 patterns. We
   added 5 negative-control trials (issue_routed → SHOULD wake) so the
   harness measures both arms of the discriminator: the defense fires
   for the targeted notify-type AND does not over-fire for unrelated
   notify-types. Without negative controls, a degenerate "always skip"
   implementation would also score 20/20 PASS. K is counted across all
   25 trials (positive that skipped + negative that woke); a trial fails
   if either arm misbehaves.

Pre-flight test-mode flag: not needed. The live channel-server is
already env-driven (MACF_AGENT_NAME, MACF_PORT=0, MACF_REGISTRY_TYPE=local
per DR-024, MACF_TMUX_SESSION). The harness uses self-signed test certs
generated on the fly with the same shape as
\`packages/macf-channel-server/test/e2e/fixtures/gen-certs.ts\`.
EOF

# --- Cleanup verification ---------------------------------------------------
echo ""
echo "=== Pattern E result ==="
echo "K/N = $K/$N_TOTAL"
echo "Rate = $RATE%"
echo "Wilson 95% lower CI = $WILSON%"
echo ""
echo "Trials: $TRIALS_TSV"
echo "Aggregate: $FIRING_TSV"
echo "Deviations: $DEVIATIONS_MD"
echo ""

# Cleanup verification — count any leftover server processes / tmux sessions.
# Match against `node ... server.js` argv pattern, not the literal string
# "macf-channel-server" anywhere in argv (which would also match the
# operator's own shell-history search lines and yield false positives).
LINGER_PROC=$(pgrep -af "node .*macf-channel-server/dist/server\.js" 2>/dev/null | grep -v "pgrep" | wc -l | tr -d '[:space:]')
LINGER_SESS=$(tmux list-sessions 2>/dev/null | awk -F: '{print $1}' | grep -c '^macf-pattern-e-trial-' | tr -d '[:space:]')
LINGER_PROC=${LINGER_PROC:-0}
LINGER_SESS=${LINGER_SESS:-0}

echo "Cleanup verification:"
echo "  lingering channel-server processes (matching macf-channel-server): $LINGER_PROC"
echo "  lingering tmux sessions (macf-pattern-e-trial-*): $LINGER_SESS"

if [ "$LINGER_PROC" != "0" ] || [ "$LINGER_SESS" != "0" ]; then
  echo "WARN: cleanup verification reported residue. Check with:"
  echo "  pgrep -af macf-channel-server"
  echo "  tmux list-sessions | grep macf-pattern-e-trial-"
fi

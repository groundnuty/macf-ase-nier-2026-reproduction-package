#!/usr/bin/env bash
# §4.4 Pattern C — Heartbeat Invariant (HB) failure-injection harness
#
# Defense being tested: tmux `session_activity` heartbeat check (per
# silent-fallback-hazards.md §"Pattern C"):
#
#   PRE=$(tmux display -p -t $SESSION '#{session_activity}')
#   tmux send-keys -t $SESSION "..." Enter
#   sleep 2
#   POST=$(tmux display -p -t $SESSION '#{session_activity}')
#   [ "$POST" -gt "$PRE" ] || echo "WARNING: tmux activity didn't advance"
#
# Injection (per pre-reg §"Pattern C"): send-keys to a tmux session whose
# pane is in a STOPPED state (kill -STOP <pid> of the foreground process
# in the pane) — input goes to stdin but isn't consumed. session_activity
# does not advance in that case. The detector should fire (POST <= PRE).
#
# Caveat: this exercises the **detector**, not the canonical Instance 3
# RC-IPC firing mode. Documented in trial details + §27 results report.
#
# Pre-reg: appendix/A5-failure-injection.md §"Pattern C"
# Pre-reg commit: 25c08da (feat/paper-attribution-validation, unpushed)
#
# Usage:
#   ./run.sh
#
# Output:
#   data/failure-injection/c/trials.tsv
#     trial_n outcome duration_ms session_name pre post details
#   data/failure-injection/firing-counts.tsv (append row)

set -euo pipefail

WORKSPACE=<HOME>/repos/groundnuty/macf-science-agent
OUT_DIR="$WORKSPACE/data/failure-injection/c"
mkdir -p "$OUT_DIR"

TRIALS_TSV="$OUT_DIR/trials.tsv"
FIRING_TSV="$WORKSPACE/data/failure-injection/firing-counts.tsv"

# Ensure firing-counts.tsv has the header
if [ ! -s "$FIRING_TSV" ]; then
  printf "pattern\tK\tN\trate\twilson_95_lower\tnotes\n" > "$FIRING_TSV"
fi

# Init trials.tsv with header
printf "trial_n\toutcome\tduration_ms\tsession_name\tpre\tpost\tdetails\n" > "$TRIALS_TSV"

N=20
K=0

cleanup_session() {
  local sess="$1" pid="${2:-}"
  [ -n "$pid" ] && kill -CONT "$pid" 2>/dev/null || true
  tmux kill-session -t "$sess" 2>/dev/null || true
}

run_trial() {
  local trial_n="$1"
  local sess="injection-c-$$-$trial_n-$(date +%s%N)"
  local start_ms end_ms dur_ms outcome details pre post pid

  start_ms=$(date +%s%3N)

  # Spin up tmux session running `cat` (reads stdin, echoes; will block when STOPPED)
  tmux new-session -d -s "$sess" 'cat'

  # Get the pane's foreground process (PID of cat)
  pid=$(tmux list-panes -t "$sess" -F '#{pane_pid}' | head -1)
  if [ -z "$pid" ]; then
    outcome="ERR_NO_PID"
    details="couldn't get pane_pid for session $sess"
    end_ms=$(date +%s%3N); dur_ms=$((end_ms - start_ms))
    cleanup_session "$sess"
    printf "%d\t%s\t%d\t%s\t-\t-\t%s\n" "$trial_n" "$outcome" "$dur_ms" "$sess" "$details" >> "$TRIALS_TSV"
    return
  fi

  # Wait briefly for tmux to fully wire up
  sleep 0.5

  # INJECT: STOP the pane process — input will land in tty buffer but won't be consumed
  kill -STOP "$pid"

  # Capture pre-activity timestamp
  pre=$(tmux display -p -t "$sess" '#{session_activity}')

  # Send-keys (the operation that would normally advance session_activity)
  tmux send-keys -t "$sess" "test message trial-$trial_n" Enter

  # Wait for activity to settle (per pattern's sleep)
  sleep 2

  # Capture post-activity timestamp
  post=$(tmux display -p -t "$sess" '#{session_activity}')

  # DEFENSE: heartbeat check — if POST > PRE, defense missed the failure (FAIL).
  # If POST <= PRE, defense correctly detected stuck pane (PASS).
  if [ "$post" -le "$pre" ]; then
    outcome="PASS"
    details="heartbeat detected stuck pane (POST<=PRE)"
    K=$((K+1))
  else
    outcome="FAIL"
    details="heartbeat missed (POST>PRE despite STOP-blocked pane); pre=$pre post=$post"
  fi

  end_ms=$(date +%s%3N); dur_ms=$((end_ms - start_ms))
  printf "%d\t%s\t%d\t%s\t%s\t%s\t%s\n" "$trial_n" "$outcome" "$dur_ms" "$sess" "$pre" "$post" "$details" >> "$TRIALS_TSV"

  # Cleanup: resume + tear down
  cleanup_session "$sess" "$pid"
}

echo "=== Pattern C (HB) failure-injection — N=$N trials ==="
echo "Pre-reg: appendix/A5-failure-injection.md §Pattern C"
echo ""
for i in $(seq 1 $N); do
  run_trial "$i"
  printf "."
done
echo ""

# Compute Wilson 95% lower CI for K/N proportion
#   p_hat = K/N
#   z = 1.96 (95% CI)
#   center = (p + z^2/(2N)) / (1 + z^2/N)
#   margin = z * sqrt(p*(1-p)/N + z^2/(4N^2)) / (1 + z^2/N)
#   lower = center - margin
WILSON=$(python3 -c "
import math
K, N = $K, $N
if N == 0: print('—'); exit()
z = 1.96
p = K/N
center = (p + z*z/(2*N)) / (1 + z*z/N)
margin = z * math.sqrt(p*(1-p)/N + z*z/(4*N*N)) / (1 + z*z/N)
lower = max(0.0, center - margin)
print(f'{lower*100:.1f}')
")

RATE=$(python3 -c "print(f'{100*$K/$N:.1f}')")

# Append to firing-counts.tsv (idempotent: replace existing pattern=C row if present)
grep -v '^C\b' "$FIRING_TSV" > "$FIRING_TSV.tmp" || true
mv "$FIRING_TSV.tmp" "$FIRING_TSV"
printf "C\t%d\t%d\t%s%%\t%s%%\theartbeat-detector test (kill -STOP injection); detector-not-firing-mode caveat documented\n" \
  "$K" "$N" "$RATE" "$WILSON" >> "$FIRING_TSV"

echo "=== Pattern C result ==="
echo "K/N = $K/$N"
echo "Rate = $RATE%"
echo "Wilson 95% lower CI = $WILSON%"
echo ""
echo "Trials: $TRIALS_TSV"
echo "Aggregate: $FIRING_TSV"

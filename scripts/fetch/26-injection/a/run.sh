#!/usr/bin/env bash
# §4.4 Pattern A — Result-Invariant Assertion (RIA) failure-injection harness
#
# Defense being tested: post-`gh comment` author-result-check (canonical
# Pattern A from `silent-fallback-hazards.md` §"Pattern A"):
#
#   gh issue comment N --body "..."
#   COMMENT_AUTHOR=$(gh issue view N --json comments --jq '.comments[-1].author.login')
#   [ "$COMMENT_AUTHOR" = "$EXPECTED_BOT" ] || { echo "FATAL: wrong author"; exit 1; }
#
# Pre-reg envisioned injection (§"Pattern A", second variant): post the
# comment via the operator's stored `gh auth login` (user PAT) — the
# comment lands as the user — then run assertion expecting the bot. This
# reproduces Instance 1's silent-fallback shape exactly.
#
# Methodology-execution-constraint pivot (approved by code-agent before
# delegation, documented in methodology-deviations.md §"Pattern A"):
# code-agent's GitHub App installation does NOT have access to the
# operator's stored user PAT (cross-identity surface). We pivot to a
# semantically equivalent injection vector:
#
#   - Post comment as `macf-code-agent[bot]` (the App identity we hold)
#   - Run the assertion with `EXPECTED_BOT="macf-science-agent[bot]"`
#     (a different bot identity than the one posting)
#   - Same assertion shape, same defense fires: exit non-zero + actor
#     mismatch named.
#
# This is a methodology-execution constraint, NOT a silent-fallback class
# issue (sister to Pattern D's perm-gap pivot). The defense surface tested
# is identical: "did the LAST comment's author match the EXPECTED_BOT?" The
# injection vector is different (different-bot vs user-attributed), but the
# assertion shape and pass criterion are unchanged.
#
# Pre-reg: appendix/A5-failure-injection.md §"Pattern A"
# Pre-reg commit: 25c08da (feat/paper-attribution-validation, unpushed)
# Delegating issue: groundnuty/macf#360
#
# Pass criterion (per pre-reg §"Pattern A"): assertion exits non-zero AND
# stderr names BOTH the actual author AND the expected author (the actor
# mismatch named).
#
# Cleanup: every comment posted gets deleted on EXIT (trap on SIGINT /
# error / normal). Verifies cleanup count == post count at end of run;
# fails loudly if cleanup count is short. Idempotent — runnable twice
# without state leak.
#
# Usage:
#   APP_ID=... INSTALL_ID=... KEY_PATH=... ./run.sh
#   (or rely on env from caller's shell — see fail-loud chain below)
#
# Output:
#   data/failure-injection/a/trials.tsv
#     trial_n outcome duration_ms details
#   data/failure-injection/firing-counts.tsv (append/upsert row)

set -euo pipefail

REPO="groundnuty/macf-science-agent"
ISSUE=16
WORKSPACE=<HOME>/repos/groundnuty/macf-science-agent
OUT_DIR="$WORKSPACE/data/failure-injection/a"
mkdir -p "$OUT_DIR"

TRIALS_TSV="$OUT_DIR/trials.tsv"
FIRING_TSV="$WORKSPACE/data/failure-injection/firing-counts.tsv"

# ---- Token bootstrap (fail-loud chain per coordination.md) ----
: "${MACF_WORKSPACE_DIR:=<HOME>/repos/groundnuty/macf}"
: "${APP_ID:?APP_ID env var required}"
: "${INSTALL_ID:?INSTALL_ID env var required}"
: "${KEY_PATH:=$MACF_WORKSPACE_DIR/.github-app-key.pem}"

mint_token() {
  local t
  t=$("$MACF_WORKSPACE_DIR/.claude/scripts/macf-gh-token.sh" \
    --app-id "$APP_ID" --install-id "$INSTALL_ID" --key "$KEY_PATH") \
    || { echo "FATAL: token mint failed" >&2; exit 1; }
  [[ "$t" == ghs_* ]] || { echo "FATAL: bad token (no ghs_ prefix)" >&2; exit 1; }
  printf '%s' "$t"
}

GH_TOKEN=$(mint_token)
export GH_TOKEN

# ---- Cleanup tracking ----
POSTED_IDS=()      # all comment IDs we successfully posted
DELETED_COUNT=0

cleanup() {
  local rc=$?
  echo ""
  echo "=== Cleanup phase ==="
  echo "Posted: ${#POSTED_IDS[@]}; deleting all..."

  # Refresh token in case run was long (well under 1h for N=20, but cheap insurance)
  GH_TOKEN=$(mint_token) && export GH_TOKEN

  for id in "${POSTED_IDS[@]}"; do
    if gh api -X DELETE "repos/$REPO/issues/comments/$id" >/dev/null 2>&1; then
      DELETED_COUNT=$((DELETED_COUNT + 1))
    else
      echo "  WARN: failed to delete comment id=$id" >&2
    fi
  done

  echo "Deleted: $DELETED_COUNT / ${#POSTED_IDS[@]}"

  # Verify issue has 0 lingering harness comments
  local remaining
  remaining=$(gh issue view $ISSUE --repo "$REPO" --json comments --jq '.comments | length' 2>/dev/null || echo "?")
  echo "Issue #$ISSUE remaining comments: $remaining"

  if [ "$DELETED_COUNT" -ne "${#POSTED_IDS[@]}" ]; then
    echo "FATAL: cleanup short (deleted=$DELETED_COUNT posted=${#POSTED_IDS[@]})" >&2
    exit 1
  fi

  exit "$rc"
}
trap cleanup EXIT INT TERM

# ---- Init outputs ----
if [ ! -s "$FIRING_TSV" ]; then
  printf "pattern\tK\tN\trate\twilson_95_lower\tnotes\n" > "$FIRING_TSV"
fi
printf "trial_n\toutcome\tduration_ms\tdetails\n" > "$TRIALS_TSV"

# ---- Trial loop ----
N=20
K=0

# Different-bot identity for EXPECTED_BOT — chosen to NOT match the actual
# author (`macf-code-agent`) so the assertion fires. The login API returns
# the bare login (no `[bot]` suffix), so we use `macf-science-agent` as the
# expected value.
EXPECTED_BOT="macf-science-agent"
ACTUAL_BOT_EXPECTED="macf-code-agent"  # what we expect the comment to land as

run_trial() {
  local trial_n="$1"
  local start_ms end_ms dur_ms outcome details body comment_id author assertion_stderr assertion_rc

  start_ms=$(date +%s%3N)

  # POST the throwaway comment via the API (returns the comment object, including ID)
  body="Pattern A harness throwaway trial $trial_n (Refs groundnuty/macf#360) — auto-deleted on harness exit."
  if ! resp=$(gh api -X POST "repos/$REPO/issues/$ISSUE/comments" -f body="$body" 2>&1); then
    end_ms=$(date +%s%3N); dur_ms=$((end_ms - start_ms))
    outcome="ERR_POST"
    details="gh api POST failed: $(echo "$resp" | tr '\n' ' ' | head -c 200)"
    printf "%d\t%s\t%d\t%s\n" "$trial_n" "$outcome" "$dur_ms" "$details" >> "$TRIALS_TSV"
    return
  fi

  comment_id=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null) || {
    end_ms=$(date +%s%3N); dur_ms=$((end_ms - start_ms))
    outcome="ERR_PARSE_ID"
    details="couldn't parse comment id from POST response"
    printf "%d\t%s\t%d\t%s\n" "$trial_n" "$outcome" "$dur_ms" "$details" >> "$TRIALS_TSV"
    return
  }

  # Track for cleanup IMMEDIATELY (before any further work that might fail)
  POSTED_IDS+=("$comment_id")

  # DEFENSE invocation: re-check author of last comment, compare to EXPECTED_BOT.
  # We capture the assertion's stderr to verify it names BOTH actual + expected.
  author=$(gh issue view $ISSUE --repo "$REPO" --json comments --jq '.comments[-1].author.login' 2>/dev/null || echo "?")

  # Run the canonical Pattern A assertion in a subshell — capture stderr + rc.
  # The subshell merges stderr to stdout via 2>&1 inside the command-sub so we
  # can grep it; rc is captured separately.
  set +e
  assertion_stderr=$(
    {
      [ "$author" = "$EXPECTED_BOT" ] || \
        { echo "FATAL: comment author mismatch — got '$author', expected '$EXPECTED_BOT'" >&2; exit 1; }
    } 2>&1
  )
  assertion_rc=$?
  set -e

  # PASS = assertion fires non-zero AND stderr names both actual + expected
  if [ "$assertion_rc" -ne 0 ] \
     && echo "$assertion_stderr" | grep -q "$author" \
     && echo "$assertion_stderr" | grep -q "$EXPECTED_BOT"; then
    outcome="PASS"
    details="assertion fired (rc=$assertion_rc); actual=$author expected=$EXPECTED_BOT; stderr names both"
    K=$((K+1))
  elif [ "$assertion_rc" -eq 0 ]; then
    outcome="FAIL_NO_FIRE"
    details="assertion exit 0 — defense didn't fire; actual=$author expected=$EXPECTED_BOT"
  else
    outcome="FAIL_INCOMPLETE"
    details="assertion fired but stderr missing actor names; rc=$assertion_rc; stderr=$(echo "$assertion_stderr" | tr '\n' ' ' | head -c 120)"
  fi

  # Note actual-author sanity check (separate from PASS/FAIL): if author isn't
  # `macf-code-agent`, that's an environmental anomaly worth flagging.
  if [ "$author" != "$ACTUAL_BOT_EXPECTED" ]; then
    details="$details; ANOMALY: actual author '$author' != expected post-as-bot '$ACTUAL_BOT_EXPECTED'"
  fi

  end_ms=$(date +%s%3N); dur_ms=$((end_ms - start_ms))
  printf "%d\t%s\t%d\t%s\n" "$trial_n" "$outcome" "$dur_ms" "$details" >> "$TRIALS_TSV"
}

echo "=== Pattern A (RIA) failure-injection — N=$N trials ==="
echo "Pre-reg: appendix/A5-failure-injection.md §Pattern A"
echo "Test issue: $REPO#$ISSUE"
echo "Injection: post-as-code-agent + EXPECTED_BOT=$EXPECTED_BOT (different-bot vector)"
echo ""

for i in $(seq 1 $N); do
  run_trial "$i"
  printf "."
done
echo ""

# ---- Aggregate: K/N + Wilson 95% lower CI ----
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

# Append/upsert pattern=A row in firing-counts.tsv (idempotent: replace if exists)
grep -v '^A\b' "$FIRING_TSV" > "$FIRING_TSV.tmp" || true
mv "$FIRING_TSV.tmp" "$FIRING_TSV"
printf "A\t%d\t%d\t%s%%\t%s%%\tpost-gh-comment author re-check (cross-identity pivot per methodology-deviations.md §Pattern A; same assertion shape — different-bot vector instead of user-vs-bot)\n" \
  "$K" "$N" "$RATE" "$WILSON" >> "$FIRING_TSV"

echo "=== Pattern A result ==="
echo "K/N = $K/$N"
echo "Rate = $RATE%"
echo "Wilson 95% lower CI = $WILSON%"
echo ""
echo "Trials: $TRIALS_TSV"
echo "Aggregate: $FIRING_TSV"
echo ""
echo "(Cleanup runs on EXIT trap.)"

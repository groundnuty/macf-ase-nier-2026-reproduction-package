#!/usr/bin/env bash
# §4.4 Pattern D — Workflow Precheck (WPC) failure-injection harness — D1 (local)
#
# Defense being tested: aggregate-fail-loud workflow precheck step (per
# silent-fallback-hazards.md §"Pattern D"). Reference implementation:
#   groundnuty/macf-devops-toolkit:.github/workflows/observability-snapshot.yml
#   step "Precheck — required secrets + variables present" (lines ~39-60).
#
# Injection: invoke the standalone precheck.sh (literal extraction of the
# canonical step's bash) with various missing-secret combinations. The
# harness varies which secrets are missing/unset/empty across N=20 trials
# per the pre-reg subcategory mix.
#
# Pass criterion (per pre-reg + delegation issue):
#   - Positive trials (defense should fire):
#       PASS = exit 1
#         AND "::error::Missing required workflow inputs:" line present
#         AND ALL injected-missing names listed (not just the first)
#         AND runbook reference present
#       FAIL otherwise.
#   - Negative-control trials (all secrets present):
#       PASS = exit 0
#       FAIL otherwise.
#
# This harness is D1 (local) only. D2 (live CI) runs separately on
# main thread via test-workflow.yml committed to macf-testbed.
#
# Pre-reg: appendix/A5-failure-injection.md §"Pattern D"
# Pre-reg commit: 25c08da (feat/paper-attribution-validation)
#
# Subcategory mix (total N=20):
#   1 secret missing (unset)        × 5 trials  (different secret each)
#   2 secrets missing (unset)       × 5 trials  (different combos each)
#   all-present negative-control    × 3 trials
#   1 secret empty-string           × 3 trials  (different secret each)
#   1 secret unset                  × 4 trials  (different secret each)
#
# Output:
#   data/failure-injection/d/trials.tsv
#     trial_n variant subcategory outcome duration_ms missing_names details
#   data/failure-injection/firing-counts.tsv (append/replace D row)

set -euo pipefail

WORKSPACE=<HOME>/repos/groundnuty/macf-science-agent
SCRIPT_DIR="$WORKSPACE/scripts/26-injection/d"
PRECHECK="$SCRIPT_DIR/precheck.sh"
OUT_DIR="$WORKSPACE/data/failure-injection/d"
mkdir -p "$OUT_DIR"

TRIALS_TSV="$OUT_DIR/trials.tsv"
FIRING_TSV="$WORKSPACE/data/failure-injection/firing-counts.tsv"

# Ensure firing-counts.tsv has the header
if [ ! -s "$FIRING_TSV" ]; then
  printf "pattern\tK\tN\trate\twilson_95_lower\tnotes\n" > "$FIRING_TSV"
fi

# Init trials.tsv with header
printf "trial_n\tvariant\tsubcategory\toutcome\tduration_ms\tmissing_names\tdetails\n" > "$TRIALS_TSV"

# Canonical 5-input REQUIRED list (matches observability-snapshot.yml)
ALL_INPUTS=(
  "TAILSCALE_OAUTH_CLIENT_ID:secret"
  "TAILSCALE_OAUTH_SECRET:secret"
  "OBS_RUNNER_SSH_KEY:secret"
  "ARCHIVE_DEPLOY_KEY:secret"
  "OBS_RUNNER_HOST:variable"
)
ALL_NAMES=(TAILSCALE_OAUTH_CLIENT_ID TAILSCALE_OAUTH_SECRET OBS_RUNNER_SSH_KEY ARCHIVE_DEPLOY_KEY OBS_RUNNER_HOST)
REQUIRED_LIST="${ALL_INPUTS[*]}"

K=0      # trials that BEHAVED CORRECTLY (positive fired correctly + negative quiet)
K_POS=0  # positive trials that fired correctly (subset of K)
N_POS=0  # positive trials run
N_NEG=0  # negative-control trials run
K_NEG=0  # negative trials that stayed quiet correctly

# Run one trial. Args:
#   $1 = trial_n
#   $2 = variant short name (used for variant column, e.g. "1miss-A")
#   $3 = subcategory ("1-missing-unset", "2-missing-unset", "all-present-control",
#                     "1-empty-string", "1-unset-isolated")
#   $4 = space-separated list of names that should be MISSING (unset or empty)
#   $5 = mode: "unset" (don't export missing names at all) or "empty" (export as "")
#   $6 = expectation: "fire" (defense should fire) or "quiet" (defense should NOT fire)
run_trial() {
  local trial_n="$1"
  local variant="$2"
  local subcategory="$3"
  local missing_list="$4"
  local mode="$5"
  local expectation="$6"

  local start_ms end_ms dur_ms
  start_ms=$(date +%s%3N)

  # Build the env for this trial: every name in ALL_NAMES gets a non-empty
  # value EXCEPT those in missing_list. For "unset" mode, missing names are
  # simply not exported. For "empty" mode, they are exported as "".
  local env_args=()
  local name
  for name in "${ALL_NAMES[@]}"; do
    if [[ " $missing_list " == *" $name "* ]]; then
      if [ "$mode" = "empty" ]; then
        env_args+=("$name=")
      fi
      # unset mode: do nothing — variable simply absent from invocation env
    else
      env_args+=("$name=trial-$trial_n-value")
    fi
  done

  # Run precheck.sh in a clean env subshell (env -i) so host env doesn't leak.
  # PATH is preserved so bash + coreutils resolve.
  local out
  local exit_code
  set +e
  out=$(env -i PATH="$PATH" REQUIRED="$REQUIRED_LIST" RUNBOOK="docs/observability-bundle-setup.md" \
        "${env_args[@]}" \
        bash "$PRECHECK" 2>&1)
  exit_code=$?
  set -e

  end_ms=$(date +%s%3N); dur_ms=$((end_ms - start_ms))

  # Extract names that appeared in ::error::  - <name> lines
  local found_names
  found_names=$(echo "$out" | sed -n 's/^::error::  - \([A-Z_][A-Z0-9_]*\).*/\1/p' | tr '\n' ',' | sed 's/,$//')

  # Classify outcome
  local outcome="FAIL"
  local details=""

  if [ "$expectation" = "quiet" ]; then
    # Negative control: precheck must exit 0 AND emit no spurious
    # ::error::Missing annotation. macf#362 follow-up (science-agent
    # tightening 2026-05-09): "exit 0" alone is too weak — a Pattern D
    # defense that exits 0 but still emits a spurious error annotation
    # should fail the trial (operator would see noise on a known-good
    # input). Tighten to BOTH exit 0 AND no error annotation in stdout.
    local has_spurious_error=0
    echo "$out" | grep -qF "::error::Missing required workflow inputs:" && has_spurious_error=1
    if [ "$exit_code" -eq 0 ] && [ "$has_spurious_error" -eq 0 ]; then
      outcome="PASS"
      details="negative-control: defense correctly stayed quiet (exit=0, no error annotation)"
      K_NEG=$((K_NEG+1))
      K=$((K+1))
    else
      outcome="FAIL"
      local why=""
      [ "$exit_code" -ne 0 ] && why="${why}exit=$exit_code(want 0); "
      [ "$has_spurious_error" -eq 1 ] && why="${why}spurious ::error::Missing on all-present; "
      details="negative-control MISFIRED — $why"
    fi
    N_NEG=$((N_NEG+1))
  else
    # Positive trial: defense must fire AND aggregate ALL missing names
    N_POS=$((N_POS+1))

    local has_missing_header=0
    local has_runbook=0
    echo "$out" | grep -qF "::error::Missing required workflow inputs:" && has_missing_header=1
    echo "$out" | grep -qF "::error::See docs/observability-bundle-setup.md for the runbook." && has_runbook=1

    # Verify ALL injected-missing names appear in the error block
    local all_listed=1
    local missing_n_listed
    local n
    for n in $missing_list; do
      if ! echo "$out" | grep -qE "^::error::  - $n "; then
        all_listed=0
        missing_n_listed="$missing_n_listed $n"
      fi
    done

    if [ "$exit_code" -eq 1 ] && [ "$has_missing_header" -eq 1 ] && [ "$has_runbook" -eq 1 ] && [ "$all_listed" -eq 1 ]; then
      outcome="PASS"
      details="defense fired correctly; aggregated all missing"
      K_POS=$((K_POS+1))
      K=$((K+1))
    else
      outcome="FAIL"
      local why=""
      [ "$exit_code" -ne 1 ] && why="${why}exit=$exit_code(want 1); "
      [ "$has_missing_header" -eq 0 ] && why="${why}no header; "
      [ "$has_runbook" -eq 0 ] && why="${why}no runbook ref; "
      [ "$all_listed" -eq 0 ] && why="${why}unlisted:$missing_n_listed; "
      details="defense MISFIRED — $why"
    fi
  fi

  # Trim missing_names for empty case (negative-control)
  [ -z "$found_names" ] && found_names="-"

  printf "%d\t%s\t%s\t%s\t%d\t%s\t%s\n" \
    "$trial_n" "$variant" "$subcategory" "$outcome" "$dur_ms" "$found_names" "$details" \
    >> "$TRIALS_TSV"
}

echo "=== Pattern D (WPC) D1 local failure-injection — N=20 trials ==="
echo "Pre-reg: appendix/A5-failure-injection.md §Pattern D"
echo "Reference: groundnuty/macf-devops-toolkit:.github/workflows/observability-snapshot.yml"
echo ""

# Subcategory 1: 1 secret missing (unset) × 5 trials, different secret each
# Cycle through ALL_NAMES (5 names → exactly 5 trials)
trial_n=0
for name in "${ALL_NAMES[@]}"; do
  trial_n=$((trial_n+1))
  run_trial "$trial_n" "1miss-${name}" "1-missing-unset" "$name" "unset" "fire"
  printf "."
done

# Subcategory 2: 2 secrets missing (unset) × 5 trials, different combo each
# Use 5 distinct combos covering all 5 names at least once
combos=(
  "TAILSCALE_OAUTH_CLIENT_ID TAILSCALE_OAUTH_SECRET"
  "OBS_RUNNER_SSH_KEY ARCHIVE_DEPLOY_KEY"
  "TAILSCALE_OAUTH_CLIENT_ID OBS_RUNNER_HOST"
  "TAILSCALE_OAUTH_SECRET ARCHIVE_DEPLOY_KEY"
  "OBS_RUNNER_SSH_KEY OBS_RUNNER_HOST"
)
combo_idx=0
for combo in "${combos[@]}"; do
  combo_idx=$((combo_idx+1))
  trial_n=$((trial_n+1))
  run_trial "$trial_n" "2miss-${combo_idx}" "2-missing-unset" "$combo" "unset" "fire"
  printf "."
done

# Subcategory 3: all-present negative-control × 3 trials
for i in 1 2 3; do
  trial_n=$((trial_n+1))
  run_trial "$trial_n" "all-present-${i}" "all-present-control" "" "unset" "quiet"
  printf "."
done

# Subcategory 4: 1 secret empty-string × 3 trials, different secret each
empty_names=(TAILSCALE_OAUTH_CLIENT_ID OBS_RUNNER_SSH_KEY OBS_RUNNER_HOST)
for name in "${empty_names[@]}"; do
  trial_n=$((trial_n+1))
  run_trial "$trial_n" "1empty-${name}" "1-empty-string" "$name" "empty" "fire"
  printf "."
done

# Subcategory 5: 1 secret unset (isolated) × 4 trials, different secret each
# Use 4 names not already covered as their own 1-miss subcategory-1 trial
# (subcat-1 already covers all 5 once; this is intentional repetition for
# the unset-vs-empty sample-size weighting per pre-reg).
unset_iso_names=(TAILSCALE_OAUTH_SECRET ARCHIVE_DEPLOY_KEY OBS_RUNNER_SSH_KEY OBS_RUNNER_HOST)
for name in "${unset_iso_names[@]}"; do
  trial_n=$((trial_n+1))
  run_trial "$trial_n" "1unset-iso-${name}" "1-unset-isolated" "$name" "unset" "fire"
  printf "."
done

echo ""
echo ""
N_TOTAL=$trial_n  # should be 20
echo "Trials run: $N_TOTAL  (positive=$N_POS, negative-control=$N_NEG)"
echo "Behaved correctly: $K  (positive correct: $K_POS/$N_POS, negative quiet: $K_NEG/$N_NEG)"

# Wilson 95% lower CI for headline (positive only) AND for all-N (positive + negative)
wilson() {
  local k="$1" n="$2"
  python3 -c "
import math
K, N = $k, $n
if N == 0: print('—'); exit()
z = 1.96
p = K/N
center = (p + z*z/(2*N)) / (1 + z*z/N)
margin = z * math.sqrt(p*(1-p)/N + z*z/(4*N*N)) / (1 + z*z/N)
lower = max(0.0, center - margin)
print(f'{lower*100:.1f}')
"
}

WILSON_POS=$(wilson "$K_POS" "$N_POS")
WILSON_ALL=$(wilson "$K" "$N_TOTAL")
RATE_POS=$(python3 -c "print(f'{100*$K_POS/$N_POS:.1f}')" 2>/dev/null || echo "—")
RATE_ALL=$(python3 -c "print(f'{100*$K/$N_TOTAL:.1f}')" 2>/dev/null || echo "—")

echo ""
echo "=== Pattern D D1 result ==="
echo "Headline (positive trials only): K_pos/N_pos = $K_POS/$N_POS  rate=$RATE_POS%  Wilson 95% lower = $WILSON_POS%"
echo "All-N (positive + negative-control): K/N = $K/$N_TOTAL  rate=$RATE_ALL%  Wilson 95% lower = $WILSON_ALL%"

# Append to firing-counts.tsv (idempotent: replace existing pattern=D row if present).
# Note per delegation: K = trials that BEHAVED CORRECTLY (positive fired + negative quiet),
# N = 20.
grep -v '^D	' "$FIRING_TSV" > "$FIRING_TSV.tmp" || true
mv "$FIRING_TSV.tmp" "$FIRING_TSV"
printf "D\t%d\t%d\t%s%%\t%s%%\taggregate-fail-loud workflow precheck (D1 local extract from observability-snapshot.yml); K=behaved-correctly (positive fired + negative quiet); D2 live CI separate\n" \
  "$K" "$N_TOTAL" "$RATE_ALL" "$WILSON_ALL" >> "$FIRING_TSV"

echo ""
echo "Trials: $TRIALS_TSV"
echo "Aggregate: $FIRING_TSV"

#!/usr/bin/env bash
# Shared helpers for scripts/analyze/*.sh
#
# All analyze scripts read frozen data and emit verifications of paper claims.
# This library provides:
#   - classify_author <login>     → "bot" | "op" | "excl"
#   - wilson_lower_95 <K> <N>     → Wilson score 95% lower CI bound (percent)
#   - assert_match <expected> <actual> <label>  → passes or fails noisily
#
# Used by analyze scripts.

# Classify a GitHub login as bot / op / excl per §03 conventions.
# Bots: per-agent App identities (*-agent[bot] OR app/*-agent — GraphQL API form)
# Excluded automation: ONLY github-actions + dependabot (in either *[bot] or
#   app/* form). §03 chose this narrow exclusion set to keep bot-share
#   conservative — github-advanced-security[bot] is treated as op (not excl).
# Op: everything else (human contributors, github-advanced-security)
classify_author() {
  local login="$1"
  case "$login" in
    # Excluded automation FIRST — checked before *-agent fallback,
    # since some excl logins (app/dependabot, app/github-actions) would
    # otherwise pattern-match as op or bot.
    github-actions\[bot\]|app/github-actions|github-actions|\
    dependabot\[bot\]|app/dependabot|dependabot)
      echo "excl"
      ;;
    *-agent\[bot\]|app/*-agent|*-agent)
      echo "bot"
      ;;
    *)
      # Everything else (human contributors, github-advanced-security[bot],
      # any other bot the project doesn't explicitly exclude) → op per §03
      echo "op"
      ;;
  esac
}

# Compute Wilson score 95% lower CI bound (percent, formatted to 1 decimal)
# Usage: wilson_lower_95 K N  → e.g. "83.9" for K=20, N=20
wilson_lower_95() {
  local K="$1" N="$2"
  if [ "$N" = "0" ] || [ -z "$N" ]; then
    echo "—"
    return
  fi
  python3 -c "
import math
K, N = $K, $N
z = 1.96
p = K/N
center = (p + z*z/(2*N)) / (1 + z*z/N)
margin = z * math.sqrt(p*(1-p)/N + z*z/(4*N*N)) / (1 + z*z/N)
lower = max(0.0, center - margin)
print(f'{lower*100:.1f}')
"
}

# Assert that an actual computed value matches a documented expected value
# Used to verify analyze-script output against §NN paper claims
# Usage: assert_match "expected" "actual" "label"
# Returns 0 on match; 1 on mismatch (and prints diagnostic)
assert_match() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  ✓ %-50s %s\n" "$label" "$actual"
    return 0
  else
    printf "  ✗ %-50s expected %s, got %s\n" "$label" "$expected" "$actual" >&2
    return 1
  fi
}

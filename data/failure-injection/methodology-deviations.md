# §4.4 Failure-injection — methodology deviations from pre-reg

Documented deviations from `26-failure-injection-pre-reg.md`, with rationale.

---

## Pattern D (WPC) — `paper-injection/d-harness` 2026-05-09

### Deviation 1: D2 repo pivot (macf-testbed → macf) + trigger pivot (workflow_dispatch → push) + substrate pivot (secrets → vars)

**Pre-reg said** (§"Pattern D — D2"): N=3 trials in `groundnuty/macf-testbed`; `workflow_dispatch` trigger; 3 fake `secrets.TEST_SECRET_A/B/C`.

**Executed**: N=3 trials in `groundnuty/macf` (NOT macf-testbed); `push` trigger on `paper-injection/d2-trial-*` branch glob (NOT workflow_dispatch); `vars.TEST_VAR_A/B/C` (NOT secrets).

**Why deviated**: code-agent's GitHub App on `macf-testbed` org has a permission gap discovered during execution:
- ❌ `actions:read` (cannot query workflow runs from this App — `gh run list` returns HTTP 403)
- ❌ `actions:write` (cannot dispatch workflow_dispatch triggers — HTTP 403 on dispatch endpoint)
- ❌ `secrets:write` (cannot configure repo secrets — HTTP 403 on actions/secrets/public-key)
- ✅ `contents:write` (push works)
- ✅ `actions_variables:write` (gh variable set works)

Per-permission gap evidence (HTTP 403 responses) captured in this branch's commit history. Sister to `feedback_app_permission_gaps_block_cross_repo_coordination.md` and `project_bare_cell_app_perm_gap.md` — code-agent's App across various org installs has had perm gaps before.

The 3-pivot rationale:
- **Repo pivot to `macf`**: code-agent has full DR-019 perms here. The push-trigger restricted to `paper-injection/d2-trial-*` glob ensures zero impact on `macf`'s routing-Action stats from §22 (which counts only the `agent-router.yml` workflow's runs).
- **Trigger pivot to push**: only requires `contents:write` (which we have).
- **Substrate pivot to vars**: canonical `observability-snapshot.yml` precheck step checks BOTH secrets AND variables (mixed list); the precheck logic is identical for either substrate. Pivoting to vars-only narrows what's tested but does NOT change the assertion shape.

**Material to §5?** Yes — but reframed per science-agent's peer-review pushback 2026-05-09. The perm-gap is **NOT** a silent-fallback class addition: it fired LOUDLY (HTTP 403 at the gh API call boundary, exit non-zero, surfaced before any work). The silent-fallback hazard signature requires "API success → semantic failure" inversion (exit 0 + semantically wrong + invisible until downstream breaks); 403 is API failure, not API success. The opposite shape.

What it IS: a **methodology-execution constraint** worth a §5 bullet:

  > "Experimental harness execution can be constrained by cross-repo App-permission scope. The Pattern D D2 trials originally targeted `groundnuty/macf-testbed` per pre-reg, but were pivoted to `groundnuty/macf` after discovering the code-agent App on macf-testbed lacked `actions:read`, `actions:write`, and `secrets:write` despite having `contents:write`. The pivot did not change the assertion shape — only narrowed the substrate (vars instead of secrets) and trigger (push instead of workflow_dispatch). A pre-flight permission audit across the experimental-substrate set should precede delegation, sister to Pattern D's own pre-flight ethos."

  Worth a follow-up issue at `groundnuty/macf` to extend `macf doctor`-style permission audits across the experimental-substrate App-install set at experiment-setup time. Filed separately from this PR.

### D2 results

3/3 trials behaved as expected:

- **Trial 1** (all-present): PASS — run conclusion success; main-work step ran; no ::error::Missing annotation. Negative-control behaviour confirmed.
- **Trial 2** (1-missing TEST_VAR_A): PASS — run conclusion failure; ::error::Missing required workflow inputs:: header + ::error::  - TEST_VAR_A (variable):: line in single error block; main-work step skipped.
- **Trial 3** (2-missing TEST_VAR_A+B): PASS — run conclusion failure; ::error::Missing required workflow inputs:: header + BOTH ::error::  - TEST_VAR_A (variable):: and ::error::  - TEST_VAR_B (variable):: lines aggregated under single header (the load-bearing aggregate-fail-loud assertion); main-work step skipped.

K_D2/N_D2 = 3/3 = 100%. Headline reports D1 K/N=20/20 (Wilson 95% lower 83.9%); D2 triangulates that the local extraction (D1) matches what GitHub Actions actually does on a real workflow run.

Run URLs in `data/failure-injection/d/d2-live-runs.tsv`.

---

## Pattern A

Pre-reg §"Pattern A" (commit 25c08da) specifies the injection variant
"post the comment as user (operator's stored `gh auth login` PAT) →
land as user → assert against expected `macf-code-agent[bot]`. This
reproduces the actual Instance 1 silent-fallback shape (rather than just
exercising the assertion logic)."

### Cross-identity pivot

**Pre-reg expectation**: code-agent has access to operator's stored
user PAT. **Reality**: code-agent runs as a GitHub App installation —
its bot token (`ghs_*`) is mintable from the App's private key, but
operator's user PAT is never exposed to the App. App-installation tokens
cannot impersonate user identities — this is by design (the GitHub
auth model boundary, not a silent-fallback hazard).

**Executed pivot**: post all 20 throwaway comments as
`macf-code-agent[bot]` (the App's identity, mintable from the key) +
set `EXPECTED_BOT="macf-science-agent[bot]"` (a DIFFERENT bot identity
than the one posting). The author re-check still fires on every trial —
exit non-zero + actor mismatch named in stderr (`actual` vs `expected`).
Same defense, different injection vector.

**Pass criterion** (per pre-reg, unchanged): assertion exits non-zero
AND error message names the actor mismatch. Both criteria met on all
20 trials.

**Material to §5?** Yes — methodology-execution constraint, NOT a
silent-fallback class addition (per the same reframing applied to
Pattern D's perm-gap finding 2026-05-09):

  > "Cross-identity injection vectors in §4.4 Pattern A's pre-reg
  > assumed access to operator's stored user PAT. Code-agent's
  > GitHub App boundary doesn't expose user PATs to App-mint flows.
  > The harness pivoted to a different-bot vector (post as bot A,
  > expect bot B) which exercises the same assertion shape — author
  > mismatch + exit non-zero + actor named in stderr. The pivot
  > narrows the substrate (bot-vs-bot rather than user-vs-bot) but
  > does not change the defense's contract or pass criterion."

  This is a known-and-bounded constraint of running paper-grade
  evaluations on App-credentialed agents — sister to Pattern D's
  cross-repo App-permission scope finding.

**Sample size**: N=20 per pre-reg. K/N=20/20 = 100%, Wilson 95% lower
CI 83.9%. Cleanup verified post-run: 0 lingering harness comments on
test-target issue (groundnuty/macf-science-agent#16).

---

## Pattern E

Pre-reg §"Pattern E" (commit 25c08da) specifies two assertions: (a) MCP
push delivered, (b) tmux pane was not woken (pre/post `session_activity`
check), and references a log key `action_path_skipped` "or equivalent".
Two reconciliations against the live (post-#355) implementation:

1. **Log key name.** The live channel-server logs
   `tmux_wake_skipped` with `reason=peer_notification_autonomous_event`
   for the Pattern E branch (`packages/macf-channel-server/src/server.ts`
   line 160). The pre-reg's "or equivalent" qualifier covers this — the
   harness asserts on the live keys. The wake-vs-skip behaviour under
   test is unchanged; only the log-event spelling differs from the
   pre-reg's draft wording. The post-#355 simplification (macf v0.2.21)
   replaced a sender-side `wake?: boolean` field with a receiver-side
   `event === 'custom'` discriminator; the architecturally-load-bearing
   property — peer_notification-with-autonomous-event → skip wake — is
   preserved.

2. **Activity timestamp choice.** Pre-reg recommends comparing
   `session_activity` pre/post curl. Empirically, `session_activity`
   advances only when an attached tmux client interacts; in the
   harness's detached test sessions (running `cat` as the wake target)
   it remains constant on BOTH positive and negative trials, which would
   make it useless as a discriminator. We additionally record
   `window_activity`, which advances on send-keys-driven pane output
   (verified manually: idle = unchanged; `cat` echoing send-keys input
   = advanced). Both timestamps appear in trials.tsv as
   `pre_sact`/`post_sact` and `pre_wact`/`post_wact`. The PASS
   criterion uses `window_activity` as the load-bearing observable;
   `session_activity` is recorded for audit. The log-event assertion
   (`tmux_wake_skipped` vs `tmux_wake_delivered`) is the primary
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
`packages/macf-channel-server/test/e2e/fixtures/gen-certs.ts`.

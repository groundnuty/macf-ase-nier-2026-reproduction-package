# Fetch scripts (frozen — paper-trail evidence)

These scripts produced the snapshots in `../../data/` at study time. They
are included **as paper-trail evidence**, not as something a reviewer can
re-run.

**Numbering note.** Script numbers are 02, 04–22, 24, 26 (with the
`26-injection/` subtree). The gaps mirror `../analyze/`: 01 was the
token-refresh utility (now at `_helpers/refresh-token.sh`), 03 was an
early classify script (the equivalent fetch is folded into 02), 23 is a
synthesis script (no separate fetch needed), 25 was a narrative-only
analysis (no separate fetch), and 27 is methodology-deviation notes
(narrative, no fetch).

Each falls into at least one of:

1. **GitHub API access** — calls `gh api` against private repositories.
   Requires a GitHub App installation token (1-hour TTL), the App's private
   key, and read scope on repositories the bundle does not own.
2. **Private session-log access** — reads JSONL transcripts under
   `~/.claude/projects/...` (operator's local Claude Code session history).
   Not redistributable.
3. **Active failure-injection harness** — runs tmux subprocesses, kills
   foreground PIDs, posts test workflow runs to live GitHub Actions.
   Requires the operator's local Linux environment plus their App credentials.
4. **Cross-machine SSH** — ssh's into the operator's MacBook to read the
   CPC predecessor's session corpus.

What reviewers can do:

- Read the scripts to see exactly how the corresponding `data/` dump was
  computed.
- Re-run the **analyze** subset (`../analyze/`) on the frozen `data/` to
  verify every paper number in the claim crosswalk.

## Scripts in this directory

| Script | Source category | Output landed in |
|---|---|---|
| `_helpers/refresh-token.sh` | (1) token mint helper | (n/a — utility used by other fetch scripts at capture time) |
| `02-multi-surface-pull.sh` | (1) gh API per-repo per-surface | `data/attribution/` |
| `04-temporal-binning.sh` | (1) gh API issue/PR comments by day | `data/op-actions.tsv` |
| `05-substrate-evolution-trace.sh` | (2) workspace inventory walk | (n/a — diagnostic) |
| `06-session-log-analysis.sh` | (2) JSONL grep | `data/session-logs/` |
| `07-per-agent-daily-and-event-types.sh` | (2) JSONL grep | `data/session-logs/per-agent-daily.tsv` |
| `08-cpc-cross-system-analysis.sh` | (4) SSH + JSONL | (stdout summary) |
| `09-instance-6-recursion-finder.sh` | (2) JSONL trace | `data/session-logs/forensic-example-*.json` |
| `10-cpc-github-side-attribution.sh` | (1) gh API CPC repos | `data/cpc-attribution/` |
| `11-rule-corpus-growth.sh` | (2) repo `.claude/rules/` walks | `data/rule-corpus-growth.tsv` |
| `12-bfa64ae4-outlier.sh` | (2) JSONL trace | (stdout) |
| `13-token-mint-burst-analysis.sh` | (2) JSONL grep | `data/burst-analysis/` |
| `14-reversal-events.sh` | (2) JSONL trace | (stdout) |
| `15-cpc-helper-adoption.sh` | (4) SSH + grep | (stdout) |
| `16-operator-vs-agent-ratio.sh` | (2) multi-repo git log | `data/operator-ratio/` |
| `17-per-failure-mode.sh` | (2) JSONL grep | `data/session-logs/per-failure-mode.tsv` |
| `18-coordination-latency.sh` | (2) JSONL grep | `data/coordination-latency/` |
| `19-robustness-checks.sh` | (2) JSONL alt-window | `data/robustness/` |
| `20-consumer-fleet-attribution.sh` | (4) SSH MacBook | `data/per-repo-logins/` (subset) |
| `21-dr2-state-placement.sh` | (1) gh API URL reachability | `data/dr2-state-placement/` |
| `22-dr4-routing-success-rate.sh` | (1) gh API workflow runs | `data/dr4-routing/` |
| `24-multi-instance-audit.sh` | (1) gh API per-instance | `data/multi-instance-audit/` |
| `26-injection/a/run.sh` | (3) failure-injection Pattern A | `data/failure-injection/a/` |
| `26-injection/c/run.sh` | (3) failure-injection Pattern C | `data/failure-injection/c/` |
| `26-injection/d/precheck.sh` | (3) Pattern D demo (env-var-driven) | (stdout) |
| `26-injection/d/run.sh` | (3) failure-injection Pattern D | `data/failure-injection/d/` |
| `26-injection/e/run.sh` | (3) failure-injection Pattern E | `data/failure-injection/e/` |
| `26-injection/e/spawn-test-server.sh` | (3) Pattern E test server | (n/a — harness component) |

For the re-runnable subset, see `../analyze/`.

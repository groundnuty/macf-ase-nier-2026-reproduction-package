# `data/` — frozen inputs to the verifier scripts

These files are the **frozen evidence** the paper's empirical claims rest
on. They were derived from a 41-day production deployment trace
(2026-04-02 through 2026-05-12); each file is a snapshot extracted
from one or more of: GitHub API responses, agent session-log JSONLs, or
intermediate aggregations.

Total size: ~660 KB. Total file count: 89.

## Layout

```
data/
├── README.md                              ← this file
│
├── op-actions.tsv                         ← canonical event ledger (top-level)
├── rule-corpus-growth.tsv                 ← canonical rule-evolution timeline (top-level)
├── outlier-04-17.tsv                      ← single-session outlier ruling-out (verify-12)
├── four-regime-comparison.tsv             ← 4-system Copilot/Cursor/CPC/MACF (verify-23)
├── instance-6-turn-ends.tsv               ← cross-agent recursion turn-ends (verify-09)
├── post-140-reversal.tsv                  ← post-#140 reversal classification (verify-14)
├── substrate-timeline.tsv                 ← workbench evolution timeline (verify-05)
│
├── per-repo-logins/                       ← per-repo per-surface author lists (verify-02)
├── session-logs/                          ← per-agent + per-failure-mode TSVs (verify-06/07/08/15/17/20)
├── cpc-attribution/                       ← CPC predecessor mis-attribution captures (verify-10)
├── coordination-latency/                  ← inter-agent latency CDF (verify-18)
├── operator-ratio/                        ← weekly bot-vs-operator commit counts (verify-16)
├── burst-analysis/                        ← anti-pattern bursts on 2026-04-15 (verify-13)
├── robustness/                            ← 10-variation sensitivity sweep (verify-19)
├── dr2-state-placement/                   ← DD2 anchor-URL reachability (verify-21)
├── dr4-routing/                           ← DD4 workflow availability (verify-22)
├── multi-instance-audit/                  ← per-instance audit summary (verify-24)
└── failure-injection/                     ← per-pattern (a/c/d/e) trial logs (verify-26/27)
```

## Layout convention

- **Subdirectories** when the data is a logical group of related files
  (multiple cuts, multiple per-event/per-trial slices, or a per-axis matrix).
- **Top-level files** when the data is a single canonical TSV/JSON read
  by one (or two) verifiers. The two largest top-level files
  (`op-actions.tsv`, `rule-corpus-growth.tsv`) are aggregate ledgers that
  multiple verifiers reference; the others are single-claim fixtures.

## Verifier ↔ data crosswalk

Run `make verify-all` from the package root to execute every verifier on
its frozen inputs. The reverse-index below answers "which verifiers read
this file or subdirectory?" and "which files feed this verifier?":

### File / subdir → verifiers

```
op-actions.tsv               ← verify-04, verify-23
rule-corpus-growth.tsv       ← verify-11
outlier-04-17.tsv            ← verify-12
four-regime-comparison.tsv   ← verify-23
instance-6-turn-ends.tsv     ← verify-09
post-140-reversal.tsv        ← verify-14
substrate-timeline.tsv       ← verify-05

per-repo-logins/             ← verify-02
session-logs/                ← verify-06, verify-07, verify-08, verify-15, verify-17, verify-20
cpc-attribution/             ← verify-10  (also referenced narratively by verify-08, verify-15)
coordination-latency/        ← verify-18
operator-ratio/              ← verify-16
burst-analysis/              ← verify-13
robustness/                  ← verify-19
dr2-state-placement/         ← verify-21
dr4-routing/                 ← verify-22
multi-instance-audit/        ← verify-24
failure-injection/           ← verify-26, verify-27
```

### Verifier → inputs

```
verify-02   per-repo-logins/
verify-04   op-actions.tsv
verify-05   substrate-timeline.tsv
verify-06   session-logs/
verify-07   session-logs/
verify-08   session-logs/
verify-09   instance-6-turn-ends.tsv
verify-10   cpc-attribution/
verify-11   rule-corpus-growth.tsv
verify-12   outlier-04-17.tsv
verify-13   burst-analysis/
verify-14   post-140-reversal.tsv
verify-15   session-logs/
verify-16   operator-ratio/
verify-17   session-logs/
verify-18   coordination-latency/
verify-19   robustness/
verify-20   session-logs/
verify-21   dr2-state-placement/
verify-22   dr4-routing/
verify-23   op-actions.tsv + four-regime-comparison.tsv
verify-24   multi-instance-audit/
verify-26   failure-injection/
verify-27   failure-injection/
```

## What each subdirectory contains

| Subdir | Captured from |
|---|---|
| `per-repo-logins/` | `gh api` queries against each (repo, surface) pair |
| `session-logs/` | `awk` / `jq` over operator-private Claude Code session-log JSONLs |
| `cpc-attribution/` | `gh api` against the CPC predecessor repo |
| `coordination-latency/` | `jq` over both agents' session-log JSONLs around a high-traffic day |
| `operator-ratio/` | `git log --pretty=format:"%ai|%an"` per repo |
| `burst-analysis/` | `awk` over session-log JSONLs |
| `robustness/` | re-runs of the 4-mechanism analysis under varied parameters |
| `dr2-state-placement/` | `gh api` URL-reachability + filesystem walk of canonical-rule tree |
| `dr4-routing/` | `gh api /repos/.../actions/runs` |
| `multi-instance-audit/` | `gh api` per-instance + canonical-rule walk |
| `failure-injection/` | live failure-injection harness runs (tmux + `kill -STOP`, mocked `gh api`, etc.) |

## What is NOT in here

- **Raw session-log JSONLs.** The shipped data are *extracts* (numeric and
  categorical fields) from operator-private session-log corpora. The raw
  logs contain prompts and tool-call payloads that cannot be redistributed;
  see `../PRIVACY.md` for the redaction methodology.
- **GitHub App private keys.** The `fetch/` scripts reference them as
  `$KEY_PATH`; the keys themselves are excluded.
- **Live API access.** All numbers in the paper compute from the snapshots
  here; nothing in `../scripts/analyze/` calls the network.

## How to verify integrity

`make verify-all` runs every verifier against this `data/` snapshot.
Each verifier exits non-zero on assertion failure; the aggregate summary
at the end of the run reports total pass count (currently 24/24).

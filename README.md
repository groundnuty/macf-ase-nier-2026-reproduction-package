# Replication package — anonymous review bundle

Companion artifact for an ASE 2026 NIER track submission (double-blind
review). All identifying information has been redacted; the framework
name is retained because it is the system being described.

## Quick start

```bash
devbox shell           # one-time install: https://www.jetify.com/devbox
make verify-all        # 166 paper-claim assertions, ~14 seconds
```

Without devbox, install `bash >= 5`, `awk`, `jq`, `python3`, `gnumake`
from your package manager (`make deps` lists what is missing). Full
walkthrough in `HOW-TO-REPRODUCE.md`.

## What's in the package

```
replication-package/
├── README.md             this file
├── HOW-TO-REPRODUCE.md   reviewer walkthrough
├── Makefile              uniform run API
├── devbox.json           pinned tools (bash, jq, gawk, python3, make)
├── PRIVACY.md            data-redaction methodology
├── LICENSE-data          CC-BY-4.0 (data + appendix)
├── LICENSE-scripts       MIT (scripts + Makefile)
│
├── data/                 frozen TSV/JSON inputs (~660 KB, 17 subdirs)
│                         see data/README.md for verifier crosswalk
│
├── scripts/
│   ├── analyze/          24 verifier scripts that read data/ and assert
│   │                     paper claims (PASS/FAIL exit; 166 assertions)
│   └── fetch/            paper-trail evidence: scripts that produced the
│                         frozen data; require GitHub App auth + private
│                         session-log access (NOT reviewer-runnable by design)
│
└── appendix/             5 methodology files (A1-A5) cited from the paper
                          where 5-page NIER limit cannot fit the detail
```

## Paper claim ↔ artifact mapping

Every empirical claim in the paper is reproducible via a `make verify-NN`
call against the frozen `data/`. The numbering matches the paper's
in-text references (`make verify-22` reproduces the §3.4 99.05% routing-
availability figure, etc.). Five claims with methodology too dense to fit
in 5 NIER pages are additionally backed by an appendix file:

| Paper anchor | Verifier | Appendix |
|---|---|---|
| §1¶3 four-regime cross-walk (Copilot / Cursor / CPC / MACF) | `make verify-23` | — |
| §3.0 + §4.2 substrate aggregate (n=2,243; 97.95% MACF / 87.27% CPC) (supp) | `make verify-02` | — |
| §3.1 anti-pattern bursts (15 + 23 on 2026-04-15) (supp) | `make verify-13` | — |
| §3.1 Mode 3+4 = 87.0% of observable failures | `make verify-17` | — |
| §3.2 DR-2 state placement (31/31 reachable; 7/8 trace to canonical rule; 6/8 PR-promotion chain) | `make verify-21` | **A2** |
| §3.3 per-agent anti-pattern decomposition | `make verify-07` | — |
| §3.3 0 true regressions in 19 days post-#140 | `make verify-14` | — |
| §3.3 consumer-fleet hook fires (8 in 14 days) | `make verify-20` | — |
| §3.3 + §4.5 substrate evolution timeline | `make verify-05` | — |
| §3.4 DR-4 routing (99.05% / 2,521 runs) | `make verify-22` | **A3** |
| §3.4 coordination latency (median 56s, n=13) | `make verify-18` | — |
| §4.2 31 → 0 mis-attributions pre/post defense | `make verify-04` | — |
| §4.2 anti-pattern share 45.4% → 3.7% (supp) | `make verify-06` | — |
| §4.2 0.17× operator-effort ratio | `make verify-16` | — |
| §4.2 CPC GitHub-side 67/943 = 7.1% (supp) | `make verify-10` | — |
| §4.2 CPC anti-pattern corpus (14,884 events / 922 sessions) (supp) | `make verify-08` | — |
| §4.2 CPC clean-control (0/922 sessions reference helper) (supp) | `make verify-15` | — |
| §4.4 per-pattern firing (RIA/PFV/HB/WPC/TD; Wilson lower CI) | `make verify-26` | **A5** |
| §4.4 + §5 methodology deviations + R10/R11/R12 reinforcements | `make verify-27` | **A5** |
| §4.4 8/8 instances with form attribution + per-pattern lit. anchors | `make verify-24` | **A4** |
| §4.4 Instance 6 recursion (19 turn-ends in 47s) | `make verify-09` | — |
| §4.5 canonical 92.3% (12/13); 78.5% across 4 surfaces | `make verify-11` | — |
| §4.5 outlier ruled out (different-project session) | `make verify-12` | — |
| §5 4-mechanism robustness (11 spec variations) | `make verify-19` | **A1** |

Anchors marked **(supp)** carry numbers that do not appear verbatim in
the 5-page paper text — they are supplementary detail (typically the
corresponding paper claim cites the broader phenomenon while the
verifier exposes the per-component decomposition or the predecessor-
system comparison). They are still byte-verifiable from frozen `data/`
and are included so the artifact bundle is complete; reviewers looking
up these specific numbers in the paper will not find them, but
`make verify-NN` reproduces them from the shipped data.

The verifier scripts' internal `assert_match` calls fail the run if any
number diverges from what the paper reports; they are the canonical
artifact for paper-claim validation.

## What this package does NOT contain

- **GitHub App private keys.** The `fetch/` scripts reference these as
  `$KEY_PATH`; the keys are excluded.
- **Live API access.** All paper numbers compute from frozen `data/`;
  `analyze/` does not call the network.
- **Operator identity / institutional affiliation.** Stripped during
  the anonymization pass; see `PRIVACY.md`.
- **Per-prompt agent transcripts.** The session-log JSONLs underlying
  three of the verifiers (12, 15, 20) are not redistributed (privacy +
  size). Frozen TSV extracts are shipped instead, so the verifiers
  themselves run deterministically; full re-extraction from raw logs
  is gated. `PRIVACY.md` details the methodology.

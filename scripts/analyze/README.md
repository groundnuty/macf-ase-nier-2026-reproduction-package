# `scripts/analyze/` — reviewer-runnable verifiers

This directory ships **24 analyze scripts** that each read frozen data from
`../../data/` and verify a specific paper claim from the ASE NIER 2026
submission.

**Total assertions byte-verified: 166** across all 24 scripts.

**Numbering note.** Script numbers are 02, 04, 05, 06, 07, 08, 09, 10, 11,
12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 26, 27. The gaps at
01, 03, 25 are intentional: 01 was a token-refresh utility (not an
analysis; lives under `../fetch/_helpers/`), 03 was an early
classify-and-aggregate script later absorbed into 02, and 25 was a
narrative synthesis report with no single number to verify.

## Quick start

From the package root:

```bash
make verify-all
```

Or run a single verifier:

```bash
make verify-22       # one §-anchor at a time
```

Reproduces 166 paper claims in ~10 seconds. Requires only `bash`, `awk`,
`python3`, `jq` — no bot tokens, no SSH, no live API calls. The pinned
toolchain is provided by the package's `devbox.json`; on a host without
devbox, install those four packages directly.

## Per-script summary

Each `make verify-NN` reproduces a paper §-anchor:

| Script | Paper §-anchor | Headline number |
|---|---|---|
| `verify-02` | §3 + §4.2 | n=2,243 actions across 5 MACF repos; 97.95% MACF / 87.27% CPC bot-share |
| `verify-04` | §4.2 | 31 events pre-#140 → 0 post; 4.43/day → 0.28/day |
| `verify-05` | §3.3 + §4.5 | Substrate evolution timeline (4 defense scripts on 2026-04-21) |
| `verify-06` | §4.2 + §3.1 | 45.4% → 3.7% anti-pattern share (12.3× reduction) |
| `verify-07` | §3.3 | Per-agent anti-pattern (SA via discipline; CA via deployment) |
| `verify-08` | §1¶3 + §4.2 | 14,884 anti-pattern events across 922 CPC sessions |
| `verify-09` | §4.4 Instance 6 | 19 alternating turn-ends in 47.0s = 9.5 cross-agent cycles |
| `verify-10` | §1¶3 + §4.2 | CPC: 67/943 = 7.1%; 5.1× higher than MACF substrate pre-#140 |
| `verify-11` | §4.5 | Canonical 92.3% (12 of 13); average 78.5% across 4 surfaces |
| `verify-12` | §4.5 | bfa64ae4 outlier ruled out (7,333 events; 0 real Bash) |
| `verify-13` | §3.1 | Burst dynamics (15+23 bursts on 2026-04-15) |
| `verify-14` | §3.3 | 0 true regressions in 19 days post-#140 (31 dedup events) |
| `verify-15` | §1¶3 | CPC = clean control (0/922 sessions reference macf-gh-token) |
| `verify-16` | §4.2 | 0.17× operator-effort: 18.29 → 3.07 op/day = 0.168 |
| `verify-17` | §3.1 | Mode 3+4 = 87.0% of observable failures |
| `verify-18` | §3.4 | Median 56s coordination latency (n=13) |
| `verify-19` | §5 | 4-mechanism model robust under 11 spec variations |
| `verify-20` | §3.3 | Substrate over-inclusive scan (13 entries; consumer 8 PPAM fires) |
| `verify-21` | §3.2 | DR-2: 31/31 URL-reachable; 6/8 canonical-rule coverage |
| `verify-22` | §3.4 | DR-4: 99.05% workflow availability (2,497/2,521) |
| `verify-23` | §1¶3 | 4-regime A/B/C/D cross-walk |
| `verify-24` | §4.4 | 8/8 instances with form attribution; n=3 strict-direct |
| `verify-26` | §4.4 | Per-pattern firing: A=20/20, B=9/10, C=20/20, D=20/20, E=25/25 |
| `verify-27` | §27 | Methodology deviations + R10/R11/R12 reinforcements |

## Bundle limitations (private-data dependencies)

3 verifiers read frozen TSVs that were extracted via SSH from the operator's
local machine (private session JSONLs). The frozen TSVs are in the bundle;
full end-to-end re-extraction would require SSH access we cannot ship:

- `verify-12` — bfa64ae4 outlier (single private session JSONL)
- `verify-15` — CPC helper-adoption (922 private CPC session logs)
- `verify-20` — consumer-fleet hook fires (private PPAM session logs)

These three still verify their numbers from the frozen TSVs we ship; only
re-extraction from the original session logs is gated. See `../../PRIVACY.md`
for the data-redaction methodology and what's intentionally excluded.

## Documented double-check findings

While building these verifiers, science-agent surfaced **6 paper-grade
discrepancies** between earlier internal reports' prose and the current
frozen data:

| # | Where | Discrepancy | Resolution |
|---|---|---|---|
| 1 | §17 prose vs TSV | 81.9% (snapshot) vs 87.0% (frozen) | Use 87.0% (byte-verifiable) |
| 2 | §11 prose vs TSV | 9 vs 8 science-agent rules | Use 78.5% across-surface average (frozen) |
| 3 | §28 §4.5 cite | "10-of-13" canonical | Correct to "12-of-13 = 92.3%" |
| 4 | §21 prose vs TSV | 7/8 = 87.5% canonical | Strict count is 6/8 = 75.0% |
| 5 | §13 prose vs TSV | 15 SA bursts only | TSV has 23 CA bursts too — strengthens claim |
| 6 | §20 / §12 | 1831 attachment events | Doesn't reproduce; load-bearing 0 real Bash holds |

All 6 findings are surfaced in the per-script output of the relevant
verifier. None contradicts a load-bearing paper claim; all are minor
refinements documented in the corresponding per-report sections.

## Reviewer instructions

From the package root:

```bash
# 1. Sanity-check tools
make deps

# 2. Run every verifier (~10s)
make verify-all

# 3. Inspect an appendix for methodology depth on one of the 5 anchored claims
cat ../../appendix/A3-routing-availability.md   # backs verify-22
```

Per ACM SIGSOFT Available Badge requirements: artifact deposited in public
archival repo; not all execution required; methodology + replication scripts
present + numbers reproduce from frozen data.

## Cross-references

- Top-level README: `../../README.md` (full paper-claim crosswalk)
- Data subdir map: `../../data/README.md` (verifier ↔ subdir relationships)
- Methodology appendices: `../../appendix/` (5 files: A1-A5)

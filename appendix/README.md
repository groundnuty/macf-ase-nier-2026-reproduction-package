# `appendix/` — methodology that doesn't fit in 5 NIER pages

Five files, each backing a specific paper claim whose methodology
requires more detail than fits in the body. The paper cites each as
`appendix~A1` through `appendix~A5`.

| File | Backs paper claim | Verifier |
|---|---|---|
| `A1-robustness-checks.md` | §5: "decomposition is robust across all 10 specification variations" — full 5-cutoff × 3-strictness × 2-filter sensitivity matrix | `make verify-19` |
| `A2-state-placement.md` | §3.2 + §225: "31/31 mis-attributed events 100% URL-reachable; 7/8 silent-fallback instances trace to a canonical rule file" — DR-2 evidence trail | `make verify-21` |
| `A3-routing-availability.md` | §3.4 + §239: "99.05% workflow availability across 2,521 routing-Action runs" — DR-4 evidence + 24-failure breakdown | `make verify-22` |
| `A4-multi-instance-audit.md` | §4.4 + §281, §283: per-instance evidence audit (8 silent-fallback instances) and per-pattern literature attribution including Meyer's design-by-contract | `make verify-24` |
| `A5-failure-injection.md` | §4.4 + §326: pre-registration + results for the 5-pattern failure-injection harness; per-pattern Wilson 95% lower CIs | `make verify-26`, `make verify-27` |

Other paper-body claims are backed directly by their verifier scripts (no
separate appendix file); see the package's top-level `README.md` for the
full claim ↔ verifier crosswalk.

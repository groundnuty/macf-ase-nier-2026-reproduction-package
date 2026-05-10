# How to reproduce

This guide walks a reviewer from a fresh checkout to verifying every
load-bearing numeric claim in the paper against the frozen data in `data/`.

Estimated wall time: **under 5 minutes** once tools are installed; the
verification itself takes about 10 seconds.

---

## 1. Tooling

The bundle uses bash + standard Unix text tools (`awk`, `jq`) plus
`python3` (for Wilson confidence-interval math in two verifiers).
No language runtime beyond Python is required.

### Option A: devbox (recommended — pinned versions)

[Devbox](https://www.jetify.com/devbox) provides a per-directory shell with
pinned tool versions, isolated from your host. One-time install:

```bash
curl -fsSL https://get.jetify.com/devbox | bash
```

Then, inside this directory:

```bash
devbox shell      # first run downloads pinned tools (~2 min)
make deps         # confirm tools are visible
```

### Option B: host install

Install from your package manager:

| OS | Command |
|---|---|
| Debian / Ubuntu | `sudo apt-get install -y bash awk jq python3 make` |
| macOS (Homebrew) | `brew install gawk jq python3 make` |
| Fedora | `sudo dnf install -y bash gawk jq python3 make` |
| Nix | the bundle's `devbox.json` lists the pinned package set |

Then run `make deps` to confirm everything is visible.

---

## 2. Reproduce all paper numbers (~10 seconds)

```bash
make verify-all
```

Runs every `scripts/analyze/NN-*.sh` in turn. Each verifier reads frozen
data slices, asserts the paper claims it covers, and exits non-zero on
any mismatch. End of run prints:

```
============================================================
All 24 verifiers PASSED. 166 paper-claim assertions reproduced
from frozen data in scripts/analyze/.
============================================================
```

---

## 3. Reproduce a single claim

```bash
make verify-22    # DR-4 routing success rate (paper §3.4)
make verify-04    # 31 → 0 mis-attributions (paper §4.2)
make verify-26    # failure-injection per-pattern firing (paper §4.4)
```

`make list` prints all 24 available `verify-NN` targets.

The README's claim-↔-verifier table tells you which verifier covers any
specific paper number.

---

## 4. Map a paper claim to its source

Each `verify-NN` script self-documents what it reads, asserts, and
reports — output ends with PASS markers per assertion. For five claims
where the methodology requires more depth than fits in 5 NIER pages,
the package additionally ships an appendix file (see `appendix/README.md`):

| Verifier | Appendix |
|---|---|
| `make verify-19` (robustness) | `appendix/A1-robustness-checks.md` |
| `make verify-21` (DR-2 state placement) | `appendix/A2-state-placement.md` |
| `make verify-22` (DR-4 routing) | `appendix/A3-routing-availability.md` |
| `make verify-24` (multi-instance + per-pattern attribution) | `appendix/A4-multi-instance-audit.md` |
| `make verify-26` / `verify-27` (failure-injection) | `appendix/A5-failure-injection.md` |

The full claim ↔ verifier mapping lives in the package's top-level
`README.md`.

---

## 5. The fetch scripts (frozen)

`scripts/fetch/` contains the helpers used to pull data from GitHub or
operator-local session logs at capture time. They required:

- a GitHub App installation token (1-hour TTL);
- read access to private repositories that hosted the framework's
  multi-agent traffic during the study window;
- in some cases, SSH access to private session-log archives on the
  operator's local machine.

These scripts are included as **paper-trail evidence** of how the frozen
`data/` was assembled. Reviewers cannot re-execute them — both because
the App credentials are not shippable and because the underlying GitHub
state moves forward in time.

The **analyze** scripts contain everything needed to verify the paper's
numbers from the snapshot in `data/`. The fetch scripts document
provenance only.

---

## 6. Bundle limitations

Three verifiers — `verify-12`, `verify-15`, `verify-20` — read frozen
TSVs that were extracted from operator-local session JSONLs. Those JSONLs
are not redistributed (privacy + size). The frozen TSV extracts ship in
`data/`, so the verifiers themselves run deterministically; what is gated
is full end-to-end re-extraction from raw session logs.

See `PRIVACY.md` for the redaction methodology and what was intentionally
excluded.

---

## 7. Troubleshooting

**`make deps` reports a missing tool.** Use devbox (Option A) or install
the named package via your OS package manager.

**A `bash` script fails with `set -eu`.** The scripts assume modern bash
(>= 5.x). On macOS the system `/bin/bash` is 3.2 — use devbox or
`brew install bash`.

**A `verify-NN` exits non-zero.** That is the failure path: the verifier
detected a mismatch between the paper claim it encodes and the frozen
data. The script prints which assertion failed and where in `data/` it
read from. No environment misconfiguration should produce this; if you
can reproduce it from a clean clone with `make deps` passing, the bundle
itself has drifted from the paper.

**Python is missing.** Two verifiers compute Wilson 95% confidence
intervals via `python3`. Install python3 (≥3.8); no third-party packages
are needed.

# Privacy + redaction methodology

This bundle ships the data and scripts that support the paper's numeric
claims. Some inputs to those analyses cannot be redistributed because they
contain private information; this document explains what was excluded,
why, and what reviewers can verify in spite of the gap.

---

## What is intentionally NOT in this bundle

### 1. Per-prompt agent session JSONLs

Claude Code persists every assistant session as a JSONL file under
`~/.claude/projects/<project-slug>/<session-id>.jsonl`. These transcripts
contain:

- the user's literal prompts (operator-authored, not redacted);
- intermediate tool-call payloads that may name files / paths / tokens
  in arguments;
- model output that may quote chat content.

The corpus underlying §3.1, §4.2, §4.4 and §4.5 of the paper consists of:

- **Operator-side MACF substrate logs** for `macf`, `macf-actions`,
  `macf-marketplace`, `macf-devops-toolkit`, `macf-science-agent`
  (~hundreds of MB across the 41-day study window).
- **Operator-side CPC predecessor logs** for the `claude-plan-composer`
  project (~1.6 GB across 922 sessions).

Both are operator-private. Shipping them anonymized would require
multi-pass scrubbing (operator chat content + tool-call args + model
quoted output) that is out of scope for an ASE NIER 2026 submission and
exceeds the privacy guarantees we can confidently make.

### 2. GitHub App private keys

`scripts/fetch/` references a per-agent installation key (1-hour TTL
tokens). The `.pem` itself is excluded from any commit by upstream
`.gitignore` rules; the App ID + Installation ID are constants that
identify accounts whose anonymity matters.

### 3. Operator handles, full names, institutional affiliations

The anonymization pass runs immediately before upload to
`anonymous.4open.science`. A two-surface grep audit (LaTeX source +
this directory) gates the upload; ZERO hits across both surfaces required.

---

## What IS shippable: derived TSV/JSONL extracts

The verifiers in `scripts/analyze/` work from **frozen extracts** of the
session-log corpora. Each extract is the output of an `awk`/`jq` pipeline
that pulled a numeric or categorical field (timestamp, event type,
helper-script reference, surface label) from the raw JSONLs. The extracts:

- contain no operator chat content;
- contain no tool-call arguments;
- contain no quoted model output;
- contain only structured numeric/categorical fields needed to verify
  the specific paper claim.

These extracts ship in `data/session-logs/`, `data/burst-analysis/`,
`data/post-140-reversal.tsv (was post-140-reversal-events/)`, and (for the CPC predecessor)
`data/cpc-attribution/` and the per-repo-logins inputs.

---

## The three SSH-derived verifiers

`verify-12`, `verify-15`, and `verify-20` read frozen TSVs that were
extracted via SSH from the operator's local machine because the
underlying session logs are too large or sensitive for local extraction
on the substrate VM:

| Verifier | Frozen TSV consumed | Why SSH-extracted |
|---|---|---|
| `verify-12` | `data/outlier-04-17.tsv` | Single-session bash-tool-call audit; needs raw session JSONL inspection |
| `verify-15` | `data/cpc-attribution/cpc-helper-adoption.tsv` | 922 CPC sessions, ~1.6 GB raw |
| `verify-20` | `data/per-repo-logins/<consumer-fleet>.txt` | Consumer-fleet PPAM session logs |

**The verifiers themselves run deterministically** from the frozen TSVs
and do not need SSH at reviewer time. What is gated by the bundle is
re-extraction of those TSVs from the source JSONLs — which would require
shipping the source JSONLs, which we don't.

This is a documented bundle limitation rather than a verification gap:
the paper's numeric claims for these verifiers reproduce byte-for-byte
from the shipped TSV extracts. Methodology for the upstream extraction
is documented inline in `scripts/analyze/12-*.sh`, `15-*.sh`, and
`20-*.sh`.

---

## What this means for ACM badges

This bundle targets the **ACM SIGSOFT Available** badge: artifact
deposited in a public archival repo, not all execution required, plus
methodology + replication scripts present and numbers reproducing from
frozen data.

The **Reusable** badge would additionally require redacted versions of
the source session JSONLs underlying `verify-12/15/20`, which is out of
scope for this submission.

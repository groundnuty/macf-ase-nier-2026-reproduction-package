# Replication package — uniform run API
#
# Quick start:
#   devbox shell          # pinned tool environment (bash, jq, gawk, python3)
#   make help             # list targets
#   make verify-all       # run all 24 verifiers (~10s)
#
# Conventions:
#   scripts/analyze/NN-*.sh   re-runnable on data/ — no network, no auth
#   scripts/fetch/NN-*.sh     frozen — required GitHub App auth at capture
#   data/                     frozen, anonymized inputs (read-only)
#   appendix/                 5 methodology files (A1-A5) cited from the paper

SHELL        := /usr/bin/env bash
.SHELLFLAGS  := -eu -o pipefail -c
.DEFAULT_GOAL := help

ROOT         := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ANALYZE_DIR  := $(ROOT)/scripts/analyze

REQUIRED_TOOLS := bash awk python3 jq sed sort wc make

VERIFIERS := 02 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 26 27

# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------

.PHONY: help
help: ## list available targets
	@printf 'Replication package — targets\n\n'
	@printf '  make %-14s %s\n' help          "this message"
	@printf '  make %-14s %s\n' deps          "check required tools (bash awk python3 jq …)"
	@printf '  make %-14s %s\n' verify-all    "run every verifier in scripts/analyze/ (~10s)"
	@printf '  make %-14s %s\n' "verify-NN"   "run a single verifier (e.g. verify-22)"
	@printf '  make %-14s %s\n' list          "list available verifiers"
	@printf '\n'
	@printf 'Verifiers reproduce 166 paper-claim assertions from frozen data.\n'
	@printf 'Each verify-NN reads data/, runs assertions, exits non-zero on mismatch.\n'
	@printf 'No GitHub auth, no network, no SSH required.\n\n'
	@printf 'Frozen scripts in scripts/fetch/ are paper-trail evidence; they\n'
	@printf 'required GitHub App auth at capture time and are not reviewer-runnable.\n'

.PHONY: deps
deps: ## check required tools are present
	@missing=0; \
	for tool in $(REQUIRED_TOOLS); do \
	  if ! command -v $$tool >/dev/null 2>&1; then \
	    echo "MISSING: $$tool" >&2; missing=1; \
	  else \
	    printf '  ok  %s\n' $$tool; \
	  fi; \
	done; \
	if [ $$missing -ne 0 ]; then \
	  echo "" >&2; \
	  echo "Run 'devbox shell' to enter the pinned-tool environment." >&2; \
	  exit 1; \
	fi

.PHONY: list
list: ## list available verifiers
	@for n in $(VERIFIERS); do \
	  s=$$(ls $(ANALYZE_DIR)/$$n-*.sh 2>/dev/null | head -1); \
	  if [ -n "$$s" ]; then echo "  verify-$$n  $${s##$(ROOT)/}"; fi; \
	done

# ---------------------------------------------------------------------------
# Per-script targets — dispatch to scripts/analyze/NN-*.sh
# ---------------------------------------------------------------------------

.PHONY: verify-%
verify-%: deps ## run a single verifier (verify-22, verify-04, …)
	@script=$$(ls $(ANALYZE_DIR)/$**.sh 2>/dev/null | head -1); \
	if [ -z "$$script" ]; then \
	  echo "no verifier matches $(ANALYZE_DIR)/$**.sh" >&2; exit 1; \
	fi; \
	bash "$$script"

# ---------------------------------------------------------------------------
# Aggregate
# ---------------------------------------------------------------------------

VERIFY_TARGETS := $(addprefix verify-,$(VERIFIERS))

.PHONY: verify-all
verify-all: deps $(VERIFY_TARGETS) ## run all 24 verifiers
	@printf '\n============================================================\n'
	@printf 'All 24 verifiers PASSED. 166 paper-claim assertions reproduced\n'
	@printf 'from frozen data in scripts/analyze/.\n'
	@printf '============================================================\n'

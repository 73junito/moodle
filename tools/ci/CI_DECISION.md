# CI Decision Artifact (`ci-decision.json`)

What `ci-decision.json` represents

- A single authoritative evaluation produced after aggregation and diff/validation checks.
- It is a policy-driven summary that answers: should CI gate (fail) this run, and why?

Where it comes from

- `ci-mode.json` — the canonical CI mode selection (dev/pr/main/audit) and source of mode.
- `manifest-run-summary.json` — canonicalized per-run RunRecords produced by the aggregator.
- `manifest-run-diff.json` — data-only diffs (regressions/new items) computed by the diff engine.
- `ci-rules.json` — the data-driven rule set used to evaluate signals and produce a decision.

What consumes it

- CI gate steps (future enforcement) that will read this file and decide to `fail` or `pass` a job.
- Orchestrators and dashboards that need a compact, auditable decision and provenance.

What "authoritative" means here

- `ci-decision.json` is the single source of truth for policy evaluation in this pipeline: it
  contains the decision (`pass`/`fail`), the applied rule-set (version/hash), a minimal
  `ruleEvaluationTrace` and provenance counters that explain how the decision was derived.

Notes

- The Decision Engine loads `ci-rules.json` if present; if the file is missing a safe
  embedded default rule-set is used so CI never breaks.
- `appliedRuleSetVersion` contains either the SHA256 of `ci-rules.json` or an embedded
  identifier when the fallback rules are used.
- The decision artifact is intentionally compact and intended for machine consumption; extra
  auditing traces are available in `ci-trace.jsonl` when tracing is enabled.

Location

- The Decision Engine script is at `tools/ci/ci-decision.ps1` and writes `ci-decision.json`.

If you want help designing rule precedence and override semantics, I can propose a
conflict-resolution approach next.

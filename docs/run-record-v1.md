# RunRecord v1 (schema freeze)

This document defines the canonical RunRecord v1 schema used by the CI aggregator.

Purpose
- Lock the RunRecord shape so downstream consumers (diff mode, dashboards, CI gates) can rely on a stable contract.
- Ensure strict vs legacy behavior is explicit.

Top-level: JSON array of RunRecord objects

RunRecord fields (required / optional)
- runId (string) — REQUIRED: unique identifier for the run.
- manifestPath (string) — REQUIRED: workspace-relative path to the manifest used for the run.
- source (string) — OPTIONAL: origin label (e.g., 'migrate', 'manual', 'ci'). Default: 'unknown'.
- status (string) — REQUIRED: one of `success`, `failed`, `skipped`.
- attemptCount (integer) — OPTIONAL: number of attempts for the run (default 0).
- attemptHistory (array) — OPTIONAL: per-attempt summary objects.
- reason (string|null) — OPTIONAL: short machine-readable reason when `status` is not `success`.

- artifacts (object) — REQUIRED (must exist, keys may be null):
  - indexPath (string|null) — path to the authoritative `index.json` for this run (if any).
  - metadataPath (string|null) — path to `metadata.json` produced by the run (if any).
  - validationPath (string|null) — path to the primary `validation-report*.json` file (if any).
  - pssaPath (string|null) — path to `pssa-results.json` (if any).
  - stepsPaths (array) — list of per-step log/artifact paths (may be empty array).

- validation (object) — OPTIONAL: normalized `pre` / `post` validation objects (nullable fields allowed).
- pssa (object|null) — OPTIONAL: parsed PSSA payload if present.

Strict vs legacy behavior
- Strict mode (`-StrictContract`): aggregator enforces the schema and will fail if any RunRecord violates the contract.
- Non-strict (default): aggregator will include legacy runs (missing or invalid `index.json`) but mark them as `status: skipped` and `reason: legacy_no_index_v1`.

Index contract (index.json)
- `index.json` is authoritative for indexed runs. The aggregator will not re-derive status or artifact locations when `index.json` is present and valid.
- Minimal expected fields in `index.json` for a valid indexed run:
  - runId
  - manifest
  - artifacts: { metadata: <path>, validation: [<path>], pssa: [<path>], steps: [<paths>] }
  - status (one of `success|failed|skipped`) — required in strict mode

Lifecycle expectations
- New runs must produce a valid `index.json` under `.github/artifacts/<sanitized-runId>/index.json`.
- Historical outputs without a valid `index.json` are `legacy-untrusted` and treated accordingly until reconciled.

Reconciliation
- Migration or reconciliation steps must be explicit, opt-in, and recorded in a separate migration tool. The aggregator will not mutate historical artifacts.

Versioning
- This is RunRecord v1. Any future schema changes require an explicit migration path and version bump.

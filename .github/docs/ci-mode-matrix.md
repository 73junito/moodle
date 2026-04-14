**CI Mode Matrix**

This document defines the canonical CI modes, their intended signal behaviour, and the rules that constrain valid combinations. Keep mode semantics explicit to avoid accidental drift between branches and to make CI behaviour reproducible.

**Canonical Modes**

| Mode  | diff   | pssa     | validation | intent |
| ----- | ------ | -------- | ---------- | ------ |
| dev   | report | baseline | baseline   | Fast iteration for feature branches — non-blocking observations. |
| pr    | report | baseline | strict     | PR-level checks: validate manifests strictly, observe diffs without gating. |
| main  | gate   | strict   | strict     | Enforcement for protected branches: regressions fail CI. |
| audit | gate   | strict   | strict     | Periodic/targeted runs for compliance and reporting; same enforcement as `main`. |

**Rule Constraints**

- Gate semantics
  - `DIFF_MODE=gate` means the workflow will fail when the diff artifact contains regressions.
  - Gate requires a valid JSON `manifest-run-diff.json`; malformed or missing JSON is treated as "no regressions" unless `strict` enforcement is explicitly required by the mode contract.

- Validation semantics
  - `MANIFEST_VALIDATION_MODE=strict` disables legacy fallbacks and treats missing/invalid `index.json` artifacts as failures.
  - `strict` validation implies the RunRecord schema contract must be satisfied for the run to be authoritative.

- PSSA semantics
  - `PSSA_MODE=strict` means new PSSA findings are treated as CI failures; a baseline file or historical acceptance policy should exist before enabling `strict` to avoid noise.
  - `PSSA_MODE=baseline` records findings for later triage but does not block CI.

**Interaction Rules / Examples**

- Allowed but non-enforcing combination:
  - `DIFF_MODE=gate` + `MANIFEST_VALIDATION_MODE=baseline` → Diff gating will still run, but manifest validation remains observational (legacy fallbacks allowed). Use with caution; prefer `strict` validation when gating.

- Unsafe / discouraged combinations:
  - `PSSA_MODE=strict` without a defined baseline or acceptance policy — may produce noisy CI failures.
  - `DIFF_MODE=gate` on short-lived feature branches without observation history — may cause premature failures.

- Recommended per-environment mapping (quick reference):
  - Local / feature: `diff=report`, `pssa=baseline`, `validation=baseline` (dev)
  - Pull request: `diff=report`, `pssa=baseline`, `validation=strict` (pr)
  - Main/protected: `diff=gate`, `pssa=strict`, `validation=strict` (main)

**Enforcement Notes**

- The workflow exposes `workflow_dispatch` inputs for `diff_mode`, `pssa_mode`, and `manifest_validation_mode` so operators may override defaults for diagnostics.
- The aggregator produces authoritative `manifest-run-summary.json` and `manifest-run-diff.json` artifacts. The gating step inspects `manifest-run-diff.json.regressions` to decide failure when `DIFF_MODE=gate`.
- When enabling `PSSA_MODE=strict`, ensure a baseline/acceptance process exists (or run strict mode first in a non-blocking environment to establish a baseline).

**Next: Mode Resolver (optional)**

Consider adding a small resolver function (e.g. `Resolve-CIMode`) that centralizes validation of the three axes, normalizes defaults, and fails early on illegal combinations. This prevents duplicated `if ($X -and $Y)` logic across scripts and ensures consistent behaviour.

Example resolver responsibilities:

- Normalize `null`/missing inputs to defaults.
- Reject unsafe combinations (e.g. `pssa=strict` without baseline).
- Compute a human-readable `mode` label (dev|pr|main|audit) for logs and PR comments.

Keeping CI mode semantics explicit and documented will prevent accidental drift and make future enforcement (A5) and trend analysis reliable.

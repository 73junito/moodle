# CI Mode (ci-mode.json)

This directory contains a small configuration and helper to control CI enforcement modes across workflows.

Files
- `ci-mode.json` — declarative presets and the currently selected preset (`currentPreset`).
- `load-ci-mode.ps1` — PowerShell helper that reads `ci-mode.json` and writes selected preset keys to `GITHUB_ENV` so workflows can consume them as environment variables.
- `../../ci-mode.json` (repo root) — generated/resolved CI mode written by `tools/ci/Resolve-CIMode.ps1` and read by helpers like `tools/ci/Get-CIMode.ps1`.

Important distinction
- `tools/ci/ci-mode.json` is the editable **preset source** (shape: `currentPreset` + `presets` map with env vars).
- `ci-mode.json` at repo root is the runtime **resolved output** (shape: `DiffMode` / `PSSAMode` / `ValidationMode` / `Label` / `Grade`).
- Edit `tools/ci/ci-mode.json` in PRs when changing rollout behavior; do not hand-edit root `ci-mode.json` unless you are intentionally updating generated output for a workflow/script contract.

Presets
- `dev` — signals enabled but purely informational; no enforcement.
- `report` — signals are reported prominently (logs/artifacts) but do not fail builds. Use this to baseline noise.
- `gate` — enforcement enabled; selected signals will fail CI runs.

How it works
- Workflows call `tools/ci/load-ci-mode.ps1` early (after checkout/setup) which writes lines like `DIFF_MODE=report` to `GITHUB_ENV`.
- Steps and scripts can read these env vars (`DIFF_MODE`, `PSSA_MODE`, `MANIFEST_VALIDATION_MODE`) to change behavior.

Rollout guidance
1. Start with `currentPreset: "report"` to observe signals without breaking builds.
2. Monitor several CI runs to ensure signal quality and acceptable noise levels.
3. Promote to `gate` (update `currentPreset`) for selective enforcement once confident.

Workflows that currently consume CI mode
- `.github/workflows/push.yml`
- `.github/workflows/ci_pipeline.yml`
- `.github/workflows/pester.yml`

Notes
- Changing `currentPreset` is a configuration-only change (no workflow edits required) and can be done in a PR to control rollout.
- The loader uses `pwsh` and writes to `GITHUB_ENV`; ensure `actions/setup-pwsh@v2` is available or run the loader under an environment with PowerShell installed.

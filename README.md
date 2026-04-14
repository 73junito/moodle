# Moodle

<p align="center"><a href="https://moodle.org" target="_blank" title="Moodle Website">
  <img src="https://raw.githubusercontent.com/moodle/moodle/main/.github/moodlelogo.svg" alt="The Moodle Logo">
</a></p>

[Moodle][1] is the World's Open Source Learning Platform, widely used around the world by countless universities, schools, companies, and all manner of organisations and individuals.

Moodle is designed to allow educators, administrators and learners to create personalised learning environments with a single robust, secure and integrated system.

## Documentation

- Read our [User documentation][3]
- Discover our [developer documentation][5]
- Take a look at our [demo site][4]

## Community

[moodle.org][1] is the central hub for the Moodle Community, with spaces for educators, administrators and developers to meet and work together.

You may also be interested in:

- attending a [Moodle Moot][6]
- our regular series of [developer meetings][7]
- the [Moodle User Association][8]

## Installation and hosting

Moodle is Free, and Open Source software. You can easily [download Moodle][9] and run it on your own web server, however you may prefer to work with one of our experienced [Moodle Partners][10].

Moodle also offers hosting through both [MoodleCloud][11], and our [partner network][10].

## License

Moodle is provided freely as open source software, under version 3 of the GNU General Public License. See our [license page][12] for more information.

[1]: https://moodle.org
[2]: https://moodle.com
[3]: https://docs.moodle.org/
[4]: https://sandbox.moodledemo.net/
[5]: https://moodledev.io
[6]: https://moodle.com/events/mootglobal/
[7]: https://moodledev.io/general/community/meetings
[8]: https://moodleassociation.org/
[9]: https://download.moodle.org
[10]: https://moodle.com/partners
[11]: https://moodle.com/cloud
[12]: https://moodledev.io/general/license

## CI Artifacts

The repository includes a deterministic CI runner that produces per-run artifacts for AppLocker IR validation. Each workflow run (see [.github/workflows/ci_pipeline.yml](.github/workflows/ci_pipeline.yml)) writes a per-run directory under `tools/runs/<runId>/` containing:

- `resilient/ir_validation_report.json` — Safe-mode evaluation results (resilient run).
- `strict/ir_validation_report.json` — Strict validation results (may intentionally fail validation).
- `ir_validation_compare.json` — Diff between resilient and strict runs for this `runId`.
- `metadata.json` — Run metadata including `RunId`, `GitCommit`, and `Timestamp`.

Where to find them in CI

- In GitHub Actions: open the workflow run, then the **Artifacts** section. The workflow uploads:
  - `ir-validation-reports` (per-run report files)
  - `ir-validation-compare` (compare artifacts)
  - `ir-validation-metadata` (run metadata files)

These artifacts make it easy to correlate CI logs with the exact run outputs for reproducible debugging.

## Local Reproduction

Run a deterministic CI evaluation locally:

```powershell
pwsh -NoProfile -File tools/ci_compare_self_heal.ps1 `
  -PolicyXml tools/tests/sample_inspect.xml `
  -SimulationReport tools/fixtures/positive_sim.json `
  -RunId local_test_001
```

Outputs will be written to:

```
tools/runs/local_test_001/
```

## Local Development & CI Validation

Run CI guards locally

Before committing, run:

```powershell
pwsh -File tools/ci/run_guards.ps1 -Root .
```

This executes:

* `ci_validate_no_pwsh_command.ps1`
* `ci_validate_no_implicit_paths.ps1`

---

## Pre-commit safety hooks

This repository enforces local commit safety via Git hooks:

* Blocks large files (>10MB)
* Blocks artifact directories (`sandbox_artifacts`, `installer_extracted`, etc.)
* Blocks unsafe file types (`.csv`, `.zip`, `.bin`, `.jsonl`, `.parquet`)

Hooks location:

```
.githooks/
```

Ensure hooks are enabled:

```powershell
git config core.hooksPath .githooks
```

---

## Run CI workflows locally (approximation)

To simulate CI pipeline behavior:

```powershell
npm install
npx grunt
pwsh -File tools/ci/run_guards.ps1 -Root .
```

For PHP tests:

```powershell
php vendor/bin/phpunit
```

---

## Deterministic runs

All CI runs generate artifacts under:

```
tools/runs/<RunId>/
```

Key outputs:

* `ir_validation_report.json`
* `ir_validation_compare.json`
* `metadata.json`


## CI Troubleshooting Tips

If you're having trouble with a specific CI run:

1. **Check the `ir_validation_compare.json`**: This file contains a side-by-side comparison of the resilient and strict mode reports. It’s useful for pinpointing where validation failed.
2. **Review the `metadata.json`**: This includes a run identifier (`RunId`), Git commit, and timestamp to help correlate the CI run with specific changes.
3. **Check for missing reports**: If the `ir_validation_report_strict.json` or `ir_validation_report_resilient.json` files are absent, it usually indicates that one of the runs (resilient or strict) failed before completing.
4. **Strict Mode Failures**: If the strict validation fails (with a non-zero exit), you’ll see detailed error messages in the strict report. This is expected behavior — reports are still written in a `finally` block even when strict validation fails.



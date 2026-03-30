# LCOV Coverage Check

A reusable composite GitHub Action (pure bash, no Node.js) that parses LCOV coverage files, enforces coverage thresholds, and posts PR comments.

## Architecture

- **`scripts/check-coverage.sh`** — Main entry point. Parses LCOV files, runs three checks (overall ratchet, new-file threshold, changed-file ratchet), generates markdown summary, and posts PR comments.
- **`scripts/retrieve-baseline.sh`** — Retrieves baseline LCOV artifact from the latest successful default-branch workflow run. Gracefully falls back to summary-only mode on any error.
- **`scripts/lib/`** — Shared library files sourced by the main scripts:
  - `common.sh` — `write_output()`, `append_summary()`
  - `lcov.sh` — LCOV parsing (`parse_lcov_overall`, `parse_lcov_per_file`), numeric helpers (`coverage_pct`, `compare_floats`, `format_pct`), extension extraction
  - `filter.sh` — Ignore-pattern matching (`should_ignore_file`, `filter_lcov_file`)
- **`action.yml`** — GitHub Actions composite action definition. Calls `retrieve-baseline.sh` then `check-coverage.sh`.

## Testing

```bash
./test/run-tests.sh
```

Tests live in `test/tests/*.sh` (13 files, ~59 tests). They are **sourced** by `test/run-tests.sh`, not executed as subprocesses. Test helpers are in `test/helpers/`. Fixtures are in `test/fixtures/`.

## Key conventions

- All scripts use `set -euo pipefail`.
- Library files use source guards (`_LIB_*_LOADED`) to prevent double-sourcing.
- Scripts resolve their own directory via `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` and source libraries relative to it.
- External dependencies: `bash`, `curl`, `jq`, `git`, `awk`, `unzip`.

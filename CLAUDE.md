# LCOV Coverage Check

A reusable composite GitHub Action (pure bash, no Node.js) that parses LCOV coverage files, enforces coverage thresholds, and posts PR comments.

## Architecture

- **`scripts/check-coverage.sh`** — Main entry point. Parses LCOV files, runs three checks (overall ratchet, new-file threshold, changed-file ratchet), generates markdown summary, and posts PR comments.
- **`scripts/retrieve-baseline.sh`** — Retrieves the baseline LCOV artifact, paging back (newest first) through recent successful default-branch runs of the same workflow to find the first that still holds a non-expired `lcov-baseline[-<label>]` artifact. Gracefully falls back to summary-only mode if none is found or on any error.
- **`scripts/lib/`** — Shared library files sourced by the main scripts:
  - `common.sh` — `write_output()`, `append_summary()`, `build_annotation_title()`, `emit_annotation()`, `begin_group()`, `end_group()`
  - `lcov.sh` — LCOV parsing (`parse_lcov_overall`, `parse_lcov_per_file`), numeric helpers (`coverage_pct`, `compare_floats`, `format_pct`), extension extraction
  - `filter.sh` — Ignore-pattern matching (`should_ignore_file`, `filter_lcov_file`)
  - `comment.sh` — PR comment section management (`build_section`, `extract_section_keys`, `replace_section`). All coverage labels share one consolidated PR comment; each label occupies its own section, independently updated via read-modify-write with retry.
- **`action.yml`** — GitHub Actions composite action definition. Calls `retrieve-baseline.sh` then `check-coverage.sh`.

## Testing

```bash
./test/run-tests.sh
```

Tests live in `test/tests/*.sh` (15 files, 77 tests, 211 assertions). They are **sourced** by `test/run-tests.sh`, not executed as subprocesses. Test helpers are in `test/helpers/`. Fixtures are in `test/fixtures/`.

## Key conventions

- All scripts use `set -euo pipefail`.
- Library files use source guards (`_LIB_*_LOADED`) to prevent double-sourcing.
- Scripts resolve their own directory via `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` and source libraries relative to it.
- External dependencies: `bash`, `curl`, `jq`, `git`, `awk`, `unzip`.
- Console output must never start a line with a file path followed by a colon (`path: …`). `actions/setup-go`
  registers a problem matcher, `^\s*(.+\.go):(?:(\d+):(\d+):)? (.*)`, with line/column optional, which turns such
  lines into error annotations. Use ` — ` as the separator, as the PASS/SKIP and per-file lines do.
- Never echo a `::` workflow command directly. Annotations go through `emit_annotation` (handles workflow-command
  escaping and the `Coverage`/`Coverage (<label>)` title). Every failure that sets `failed=true` must emit an
  error annotation; per-file failures (new-file, changed-file) also pass the file path so the annotation gets
  `file=<path>,line=1`, while repo-wide failures (the overall ratchet, input validation) pass no file.
  Collapsible log groups go through `begin_group`/`end_group`; only the per-file listing is grouped.

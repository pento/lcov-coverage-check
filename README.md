# LCOV Coverage Check

A reusable composite GitHub Action that parses LCOV coverage files, reports coverage summaries, and optionally enforces coverage thresholds by comparing against a baseline.

## Features

- **Automatic baseline management**: Stores coverage on main-branch pushes, auto-retrieves it on PRs
- **Language-agnostic**: Works with any language that produces LCOV data (Dart, Go, Python, TypeScript, C/C++, Ruby, etc.) — file extensions are derived automatically from the LCOV data
- **Summary-only mode**: Report overall and per-file coverage without enforcing any rules
- **Overall ratchet check**: Ensure overall coverage does not decrease compared to a baseline
- **New-file threshold**: Require new files to meet a minimum coverage percentage
- **Changed-file ratchet**: Prevent per-file coverage from decreasing on modified files
- **PR comments**: Automatically post or update a coverage summary comment on pull requests
- **Step summary**: Write a markdown summary to `$GITHUB_STEP_SUMMARY`

## Usage

### Basic usage (recommended)

```yaml
- name: Run tests with coverage
  run: flutter test --coverage

- name: Check coverage
  uses: pento/lcov-coverage-check@main
  with:
    new-file-minimum-coverage: 80
    path: 'lib/'
    changed-file-no-decrease: true
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

- **On main push**: summary report + stores LCOV as `lcov-baseline` artifact
- **On PR**: auto-retrieves baseline, auto-detects git refs, runs full comparison, posts PR comment, stores `lcov-coverage` artifact

### Summary-only mode (no token)

Report coverage without enforcing any rules or managing artifacts. Always passes.

```yaml
- name: Coverage summary
  uses: pento/lcov-coverage-check@main
```

### Full workflow example

```yaml
name: Coverage

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Run tests with coverage
        run: flutter test --coverage

      - name: Check coverage
        uses: pento/lcov-coverage-check@main
        with:
          new-file-minimum-coverage: 80
          path: 'lib/'
          changed-file-no-decrease: true
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `lcov-file` | no | `coverage/lcov.info` | Path to current LCOV coverage file |
| `new-file-minimum-coverage` | no | `80` | Minimum coverage percentage for new files (0-100) |
| `path` | no | `lib/` | Only enforce file-level checks under this path prefix. Empty = all paths |
| `changed-file-no-decrease` | no | `true` | Require that per-file coverage of modified files does not decrease vs baseline |
| `github-token` | no | `''` | GitHub token for PR comments and artifact management. If empty, runs in summary-only mode |

## Outputs

| Output | Description |
|--------|-------------|
| `overall-coverage` | Current overall coverage percentage (e.g., `87.50`) |
| `baseline-coverage` | Baseline coverage percentage (empty if summary-only) |
| `passed` | `'true'` or `'false'` |
| `baseline-artifact-downloaded` | `'true'` if baseline was auto-retrieved from a previous run |

## Automatic Baseline Management

When `github-token` is provided, the action automatically manages baseline coverage artifacts:

1. **On pushes to the default branch** (e.g., `main`): the current LCOV file is uploaded as an `lcov-baseline` artifact, overwriting any previous baseline.
2. **On pull requests**: the action retrieves the `lcov-baseline` artifact from the latest successful default-branch run of the same workflow. It also extracts `base.sha` and `head.sha` from the PR event payload for `git diff` operations.
3. **On pull requests**: the current LCOV file is also uploaded as an `lcov-coverage` artifact.

If no baseline artifact is found (e.g., first run), the action falls back to summary-only mode gracefully.

### Token permissions

The `github-token` needs the following permissions:
- `actions: read` — to list workflow runs and download artifacts
- `pull-requests: write` — to post/update PR comments

### Artifact retention

Baseline artifacts follow your repository's default artifact retention policy. You can configure this in your repository settings or workflow file.

## How it works

### Summary-only mode (no `github-token` or no baseline available)

- Parses the LCOV file and prints overall + per-file coverage
- Writes a markdown summary to `$GITHUB_STEP_SUMMARY`
- Always exits 0 and sets `passed` to `true`

### Comparison mode (baseline auto-retrieved)

1. **Overall ratchet**: Current overall coverage must be >= baseline overall coverage
2. **New-file check**: New source files (filtered to file types found in the LCOV data, detected via `git diff --diff-filter=A`) must meet the `new-file-minimum-coverage` threshold. Files with no instrumentable lines (`LF:0`) pass automatically. Files not found in the LCOV data are treated as 0% coverage.
3. **Changed-file ratchet**: If `changed-file-no-decrease` is `true`, modified source files (filtered to file types found in the LCOV data) must not have decreased per-file coverage. Files not present in the baseline LCOV data are skipped.

### PR comments

When `github-token` is provided and the action runs in a pull request context, a markdown comment is posted (or updated) on the PR. The comment is identified by a hidden HTML marker so it gets updated on subsequent pushes rather than creating duplicate comments.

## Edge cases

- **Empty or missing LCOV files**: Treated as 0% coverage (not an error)
- **First run (no baseline)**: Runs in summary-only mode. Baseline stored for next PR.
- **Expired artifact**: Filtered by `expired == false`. Graceful fallback to summary-only.
- **Fork PRs**: Token may lack `actions: read`. ERR trap handles graceful fallback.
- **New file not in LCOV data**: Treated as 0% coverage, fails if below threshold
- **New file with `LF:0`**: No instrumentable lines, passes automatically
- **Modified file not in baseline LCOV**: Skipped (new to coverage tracking)
- **Modified file not in current LCOV**: Treated as 0% coverage

## Local development

The script can be run locally without GitHub Actions:

```bash
INPUT_LCOV_FILE=coverage/lcov.info \
INPUT_LCOV_BASE=baseline/lcov.info \
INPUT_BASE_REF=main \
INPUT_HEAD_REF=HEAD \
INPUT_NEW_FILE_MINIMUM_COVERAGE=80 \
INPUT_PATH=lib/ \
INPUT_CHANGED_FILE_NO_DECREASE=true \
INPUT_GITHUB_TOKEN="" \
  ./scripts/check-coverage.sh
```

### Running tests

```bash
./test/run-tests.sh
```

## License

MIT License. See [LICENSE](LICENSE) for details.

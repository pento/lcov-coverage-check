# LCOV Coverage Check

A reusable composite GitHub Action that parses LCOV coverage files, reports coverage summaries, and optionally enforces coverage thresholds by comparing against a baseline.

## Features

- **Summary-only mode**: Report overall and per-file coverage without enforcing any rules
- **Overall ratchet check**: Ensure overall coverage does not decrease compared to a baseline
- **New-file threshold**: Require new files to meet a minimum coverage percentage
- **Changed-file ratchet**: Prevent per-file coverage from decreasing on modified files
- **PR comments**: Automatically post or update a coverage summary comment on pull requests
- **Step summary**: Write a markdown summary to `$GITHUB_STEP_SUMMARY`

## Usage

### Summary-only mode

Report coverage without enforcing any rules. Always passes.

```yaml
- name: Coverage summary
  uses: your-org/lcov-coverage-check@v1
  with:
    lcov-file: coverage/lcov.info
```

### Comparison mode with baseline

Compare current coverage against a baseline and enforce thresholds.

```yaml
- name: Check coverage
  uses: your-org/lcov-coverage-check@v1
  with:
    lcov-file: coverage/lcov.info
    lcov-base: coverage/baseline.lcov.info
    base-ref: ${{ github.event.pull_request.base.sha }}
    head-ref: ${{ github.event.pull_request.head.sha }}
    new-file-minimum-coverage: '80'
    changed-file-no-decrease: 'true'
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Full workflow example

```yaml
name: Coverage

on:
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

      - name: Download baseline coverage
        # Fetch baseline coverage from your main branch artifact, cache, etc.
        run: |
          # Example: download from artifacts
          gh run download --name coverage-baseline --dir baseline/ || true

      - name: Check coverage
        uses: your-org/lcov-coverage-check@v1
        with:
          lcov-file: coverage/lcov.info
          lcov-base: baseline/lcov.info
          base-ref: ${{ github.event.pull_request.base.sha }}
          head-ref: ${{ github.event.pull_request.head.sha }}
          new-file-minimum-coverage: '80'
          new-file-path-prefix: 'lib/'
          changed-file-no-decrease: 'true'
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `lcov-file` | **yes** | — | Path to current LCOV coverage file |
| `lcov-base` | no | `''` | Path to baseline LCOV file. If empty, runs in summary-only mode |
| `base-ref` | no | `''` | Git ref for base branch (for detecting new/changed files via `git diff`) |
| `head-ref` | no | `HEAD` | Git ref for PR head |
| `new-file-minimum-coverage` | no | `80` | Minimum coverage percentage for new files (0-100) |
| `new-file-path-prefix` | no | `lib/` | Only enforce new-file threshold under this prefix. Empty = all paths |
| `changed-file-no-decrease` | no | `true` | Require that per-file coverage of modified files does not decrease vs baseline |
| `github-token` | no | `''` | GitHub token for posting PR summary comment. If empty, no comment is posted |

## Outputs

| Output | Description |
|--------|-------------|
| `overall-coverage` | Current overall coverage percentage (e.g., `87.50`) |
| `baseline-coverage` | Baseline coverage percentage (empty if summary-only) |
| `passed` | `'true'` or `'false'` |

## How it works

### Summary-only mode (no `lcov-base`)

- Parses the LCOV file and prints overall + per-file coverage
- Writes a markdown summary to `$GITHUB_STEP_SUMMARY`
- Always exits 0 and sets `passed` to `true`

### Comparison mode (with `lcov-base`)

1. **Overall ratchet**: Current overall coverage must be >= baseline overall coverage
2. **New-file check**: If `base-ref` is set, new `.dart` files (detected via `git diff --diff-filter=A`) must meet the `new-file-minimum-coverage` threshold. Files with no instrumentable lines (`LF:0`) pass automatically. Files not found in the LCOV data are treated as 0% coverage.
3. **Changed-file ratchet**: If `changed-file-no-decrease` is `true` and `base-ref` is set, modified `.dart` files must not have decreased per-file coverage. Files not present in the baseline LCOV data are skipped.

### PR comments

When `github-token` is provided and the action runs in a pull request context, a markdown comment is posted (or updated) on the PR. The comment is identified by a hidden HTML marker so it gets updated on subsequent pushes rather than creating duplicate comments.

## Edge cases

- **Empty or missing LCOV files**: Treated as 0% coverage (not an error)
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
INPUT_NEW_FILE_PATH_PREFIX=lib/ \
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

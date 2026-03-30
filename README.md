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
    path: "lib/"
    changed-file-no-decrease: true
    ignore-patterns: |
      *.g.dart
      *.freezed.dart
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

> **Note**: When using `github-token`, your workflow needs `actions: read` permission. See [Token permissions](#token-permissions).

If your project has source code in multiple directories, specify multiple path prefixes (one per line):

```yaml
- name: Check coverage
  uses: pento/lcov-coverage-check@main
  with:
    path: |
      lib/
      src/
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
    permissions:
      actions: read
      contents: read
      pull-requests: write
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
          path: "lib/"
          changed-file-no-decrease: true
          ignore-patterns: |
            *.g.dart
            *.freezed.dart
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Multi-language workflows

If your repo produces multiple LCOV files (e.g., Go backend + TypeScript frontend), use `coverage-label` to run the action multiple times without conflicts:

```yaml
- name: Check Go coverage
  uses: pento/lcov-coverage-check@main
  with:
    lcov-file: go-coverage.lcov
    coverage-label: go
    path: ""
    github-token: ${{ secrets.GITHUB_TOKEN }}

- name: Check TypeScript coverage
  uses: pento/lcov-coverage-check@main
  with:
    lcov-file: ts-coverage.lcov
    coverage-label: frontend
    path: "src/"
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

Each label gets its own PR comment (identified by a label-specific HTML marker), baseline artifact (e.g., `lcov-baseline-go`), and PR coverage artifact (e.g., `lcov-coverage-frontend`).

Labels are normalized to lowercase alphanumeric characters and hyphens. If the action detects that multiple coverage checks are running without consistent `coverage-label` usage (e.g., some steps have labels and others don't), a visible warning is added to the PR comment.

## Inputs

| Input                       | Required | Default              | Description                                                                               |
| --------------------------- | -------- | -------------------- | ----------------------------------------------------------------------------------------- |
| `lcov-file`                 | no       | `coverage/lcov.info` | Path to current LCOV coverage file                                                        |
| `new-file-minimum-coverage` | no       | `80`                 | Minimum coverage percentage for new files (0-100)                                         |
| `path`                      | no       | `lib/`               | Path prefixes for file-level checks, one per line. Empty = all paths                      |
| `changed-file-no-decrease`  | no       | `true`               | Require that per-file coverage of modified files does not decrease vs baseline            |
| `ignore-patterns`           | no       | `''`                 | File patterns to exclude from coverage checks (one glob pattern per line)                 |
| `coverage-label`            | no       | `''`                 | Label to distinguish multiple coverage checks. Enables separate PR comments and artifacts |
| `github-token`              | no       | `''`                 | GitHub token for PR comments and artifact management. If empty, runs in summary-only mode |

## Outputs

| Output                         | Description                                                 |
| ------------------------------ | ----------------------------------------------------------- |
| `overall-coverage`             | Current overall coverage percentage (e.g., `87.50`)         |
| `baseline-coverage`            | Baseline coverage percentage (empty if summary-only)        |
| `passed`                       | `'true'` or `'false'`                                       |
| `baseline-artifact-downloaded` | `'true'` if baseline was auto-retrieved from a previous run |

## Automatic Baseline Management

When `github-token` is provided, the action automatically manages baseline coverage artifacts:

1. **On pushes to the default branch** (e.g., `main`): the current LCOV file is uploaded as an `lcov-baseline` artifact, overwriting any previous baseline.
2. **On pull requests**: the action retrieves the `lcov-baseline` artifact from the latest successful default-branch run of the same workflow. It also extracts `base.sha` and `head.sha` from the PR event payload for `git diff` operations.
3. **On pull requests**: the current LCOV file is also uploaded as an `lcov-coverage` artifact.

When `coverage-label` is set, artifact names are suffixed (e.g., `lcov-baseline-go`, `lcov-coverage-frontend`). Each label tracks its own independent baseline. **Note:** adding a `coverage-label` to an existing workflow is a breaking change — the first PR will run in summary-only mode until the default branch creates the new labeled baseline artifact.

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

### Ignore patterns

When `ignore-patterns` is provided, matching files are excluded from all coverage checks:

- **LCOV filtering**: Records for matching files are removed from LCOV data before any calculations, affecting both overall and per-file coverage numbers.
- **New-file check**: New files matching a pattern are skipped.
- **Changed-file ratchet**: Modified files matching a pattern are skipped.

Patterns use standard glob syntax: `*` matches any characters (including path separators), `?` matches a single character, and `[...]` matches character classes. One pattern per line.

Common examples:

- `*.g.dart` — Dart code generation output
- `*.freezed.dart` — Freezed-generated files
- `*.generated.go` — Go generated code
- `lib/generated/*` — all files under a directory

### PR comments

When `github-token` is provided and the action runs in a pull request context, a markdown comment is posted (or updated) on the PR. The comment is identified by a hidden HTML marker so it gets updated on subsequent pushes rather than creating duplicate comments. When `coverage-label` is provided, each label gets its own comment, preventing multiple coverage checks from overwriting each other.

### Shallow clones and fetch-depth

For new/modified file detection, the action needs access to both the base and head commits. It will automatically attempt to fetch them from the remote, but if your checkout uses a very restrictive configuration (e.g., no remote access), you may need `fetch-depth: 0` in your `actions/checkout` step. If the refs cannot be fetched or resolved, a `::warning::` annotation is emitted and the action continues without file-level checks rather than failing.

## Edge cases

- **Empty or missing LCOV files**: Treated as 0% coverage (not an error)
- **First run (no baseline)**: Runs in summary-only mode. Baseline stored for next PR.
- **Expired artifact**: Filtered by `expired == false`. Graceful fallback to summary-only.
- **Fork PRs**: Token may lack `actions: read`. ERR trap handles graceful fallback.
- **New file not in LCOV data**: Treated as 0% coverage, fails if below threshold
- **New file with `LF:0`**: No instrumentable lines, passes automatically
- **Modified file not in baseline LCOV**: Skipped (new to coverage tracking)
- **Modified file not in current LCOV**: Treated as 0% coverage
- **Ignored files**: Completely excluded from LCOV data, overall coverage, and per-file checks
- **Changing a `coverage-label`**: Renaming a label orphans the old comment (it won't be updated or deleted) and the old baseline artifact is no longer used. The new label starts fresh.

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
INPUT_IGNORE_PATTERNS="" \
INPUT_COVERAGE_LABEL="" \
INPUT_GITHUB_TOKEN="" \
  ./scripts/check-coverage.sh
```

### Running tests

```bash
./test/run-tests.sh
```

## License

MIT License. See [LICENSE](LICENSE) for details.

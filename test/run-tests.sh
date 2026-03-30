#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# run-tests.sh — Test suite for check-coverage.sh
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK_SCRIPT="$PROJECT_DIR/scripts/check-coverage.sh"
RETRIEVE_SCRIPT="$PROJECT_DIR/scripts/retrieve-baseline.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors (if terminal supports it)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "  ${GREEN}PASS${NC}: $1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "  ${RED}FAIL${NC}: $1"
}

run_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo ""
  echo -e "${YELLOW}Test ${TESTS_RUN}: $1${NC}"
}

# ---------------------------------------------------------------------------
# Helper: create a temp git repo with baseline and head commits
# Returns the temp dir path. Sets GIT_BASE_REF and GIT_HEAD_REF.
# Args:
#   $1 - associative: "base" files (space-separated "path:content" pairs)
#   $2 - associative: "head" files to add (space-separated "path:content" pairs)
#   $3 - associative: "head" files to modify (space-separated "path:content" pairs)
# ---------------------------------------------------------------------------
setup_git_repo() {
  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-test-XXXXXX")"

  (
    cd "$tmpdir"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"

    # Base commit with files
    local base_files="$1"
    if [[ -n "$base_files" ]]; then
      for entry in $base_files; do
        local fpath="${entry%%:*}"
        local fcontent="${entry#*:}"
        mkdir -p "$(dirname "$fpath")"
        echo "$fcontent" > "$fpath"
        git add "$fpath"
      done
    fi
    git commit -q --allow-empty -m "base commit"
    git tag base_ref

    # Head commit: add new files
    local new_files="${2:-}"
    if [[ -n "$new_files" ]]; then
      for entry in $new_files; do
        local fpath="${entry%%:*}"
        local fcontent="${entry#*:}"
        mkdir -p "$(dirname "$fpath")"
        echo "$fcontent" > "$fpath"
        git add "$fpath"
      done
    fi

    # Head commit: modify existing files
    local mod_files="${3:-}"
    if [[ -n "$mod_files" ]]; then
      for entry in $mod_files; do
        local fpath="${entry%%:*}"
        local fcontent="${entry#*:}"
        echo "$fcontent" > "$fpath"
        git add "$fpath"
      done
    fi

    git commit -q --allow-empty -m "head commit"
    git tag head_ref
  )

  echo "$tmpdir"
}

cleanup_git_repo() {
  if [[ -n "${1:-}" && -d "$1" ]]; then
    rm -rf "$1"
  fi
}

# ---------------------------------------------------------------------------
# Test 1: Summary-only mode
# ---------------------------------------------------------------------------
run_test "Summary-only mode: reports correctly, exits 0"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "Summary-only mode"; then
  pass "output contains 'Summary-only mode'"
else
  fail "output missing 'Summary-only mode'"
fi

if echo "$output" | grep -q "87.50%"; then
  pass "output contains correct overall coverage (87.50%)"
else
  fail "output missing '87.50%' coverage"
fi

if echo "$output" | grep -q "Result: PASS"; then
  pass "output contains 'Result: PASS'"
else
  fail "output missing 'Result: PASS'"
fi

# ---------------------------------------------------------------------------
# Test 2: Overall coverage increased
# ---------------------------------------------------------------------------
run_test "Overall coverage increased: exits 0"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "Coverage did not decrease"; then
  pass "output confirms coverage did not decrease"
else
  fail "output missing coverage increase confirmation"
fi

# ---------------------------------------------------------------------------
# Test 3: Overall coverage decreased
# ---------------------------------------------------------------------------
run_test "Overall coverage decreased: exits 1 with clear message"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/decreased.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 1 ]]; then
  pass "exit code is 1"
else
  fail "expected exit code 1, got $exit_code"
fi

if echo "$output" | grep -q "Overall coverage decreased"; then
  pass "output contains 'Overall coverage decreased'"
else
  fail "output missing 'Overall coverage decreased'"
fi

if echo "$output" | grep -q "Result: FAIL"; then
  pass "output contains 'Result: FAIL'"
else
  fail "output missing 'Result: FAIL'"
fi

# ---------------------------------------------------------------------------
# Test 4: New file above threshold
# ---------------------------------------------------------------------------
run_test "New file above threshold: exits 0"

# Create a git repo where new_widget.dart is a new file
tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a lib/src/widget_b.dart:b" \
  "lib/src/new_widget.dart:new" \
  ""
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/new-file.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="40" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "50.00% >= 40%"; then
  pass "output shows new file passed threshold"
else
  fail "output missing threshold pass message"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 5: New file below threshold
# ---------------------------------------------------------------------------
run_test "New file below threshold: exits 1"

tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a lib/src/widget_b.dart:b" \
  "lib/src/new_widget.dart:new" \
  ""
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/new-file.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 1 ]]; then
  pass "exit code is 1"
else
  fail "expected exit code 1, got $exit_code"
fi

if echo "$output" | grep -q "50.00% coverage (minimum: 80%)"; then
  pass "output shows new file failed threshold"
else
  fail "output missing threshold fail message"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 6: Empty baseline (0% → any) — exits 0
# ---------------------------------------------------------------------------
run_test "Empty baseline (0% → any): exits 0"

# Create an empty baseline file
empty_baseline="$(mktemp "${TMPDIR:-/tmp}/empty-baseline-XXXXXX")"
: > "$empty_baseline"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$empty_baseline" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

rm -f "$empty_baseline"

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "Baseline: 0.00%"; then
  pass "output shows baseline as 0.00%"
else
  fail "output missing baseline 0.00%"
fi

if echo "$output" | grep -q "Coverage did not decrease"; then
  pass "coverage did not decrease (0% -> 87.50%)"
else
  fail "output missing coverage pass message"
fi

# ---------------------------------------------------------------------------
# Test 7: New file not in LCOV — exits 1 (0% coverage)
# ---------------------------------------------------------------------------
run_test "New file not in LCOV: exits 1 (0% coverage)"

# Create a git repo where a file is added but not in any LCOV data
tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a lib/src/widget_b.dart:b" \
  "lib/src/unknown_widget.dart:new" \
  ""
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 1 ]]; then
  pass "exit code is 1"
else
  fail "expected exit code 1, got $exit_code"
fi

if echo "$output" | grep -q "not found in LCOV data"; then
  pass "output reports file not found in LCOV"
else
  fail "output missing 'not found in LCOV data'"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 8: Changed file coverage increased — exits 0
# ---------------------------------------------------------------------------
run_test "Changed file coverage increased: exits 0"

# widget_a.dart: baseline 75%, current 100% (increased)
# widget_b.dart: baseline 50%, current 75% (increased)
tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a lib/src/widget_b.dart:b" \
  "" \
  "lib/src/widget_a.dart:a-modified lib/src/widget_b.dart:b-modified"
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "Changed File Ratchet Check"; then
  pass "output contains 'Changed File Ratchet Check'"
else
  fail "output missing 'Changed File Ratchet Check'"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 9: Changed file coverage decreased — exits 1
# ---------------------------------------------------------------------------
run_test "Changed file coverage decreased: exits 1"

# Use decreased.lcov.info as current — widget_a goes from 75% to 25%
tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a lib/src/widget_b.dart:b" \
  "" \
  "lib/src/widget_a.dart:a-modified"
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/decreased.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 1 ]]; then
  pass "exit code is 1"
else
  fail "expected exit code 1, got $exit_code"
fi

if echo "$output" | grep -q "coverage decreased"; then
  pass "output reports coverage decrease"
else
  fail "output missing coverage decrease message"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 10: Changed file not in baseline (new to coverage) — skip, exits 0
# ---------------------------------------------------------------------------
run_test "Changed file not in baseline (new to coverage): skip, exits 0"

# Create a scenario where a modified file has no baseline LCOV entry
# We'll use current.lcov.info which has widget_a and widget_b,
# but use an empty baseline so neither file has baseline coverage data.
# Modify widget_a so it shows as modified in git diff.

tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a" \
  "" \
  "lib/src/widget_a.dart:a-modified"
)"

empty_baseline="$(mktemp "${TMPDIR:-/tmp}/empty-baseline-XXXXXX")"
: > "$empty_baseline"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$empty_baseline" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

rm -f "$empty_baseline"

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "SKIP.*not in baseline"; then
  pass "output shows file skipped (not in baseline)"
else
  fail "output missing skip message for file not in baseline"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 11: PR comment is posted when event payload has PR number
# ---------------------------------------------------------------------------
run_test "PR comment posted when GITHUB_EVENT_PATH has pull_request.number"

# Create a fake event payload
event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

# Create a mock curl that logs its calls
mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
# Return empty array for GET (list comments), empty object for POST/PATCH
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
else
  echo '[]'
fi
MOCKCURL
chmod +x "${mock_bin}/curl"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "Posting PR Comment"; then
  pass "output contains 'Posting PR Comment'"
else
  fail "output missing 'Posting PR Comment'"
fi

if echo "$output" | grep -q "Created new PR comment"; then
  pass "output contains 'Created new PR comment'"
else
  fail "output missing 'Created new PR comment'"
fi

# Verify curl was called with the correct PR number in the URL
if grep -q "issues/42/comments" "$curl_log" 2>/dev/null; then
  pass "curl called with correct PR number (42)"
else
  fail "curl not called with correct PR number"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 12: PR comment skipped when no event payload
# ---------------------------------------------------------------------------
run_test "PR comment skipped when GITHUB_EVENT_PATH is not set"

output="$(
  unset GITHUB_EVENT_PATH
  GITHUB_REPOSITORY="owner/repo" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if ! echo "$output" | grep -q "Posting PR Comment"; then
  pass "no PR comment attempted (no event payload)"
else
  fail "PR comment should not be attempted without event payload"
fi

# ---------------------------------------------------------------------------
# Test 13: PR comment skipped when event payload has no PR number
# ---------------------------------------------------------------------------
run_test "PR comment skipped when event payload has no PR number (e.g. push event)"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"ref": "refs/heads/main"}' > "$event_payload"

output="$(
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if ! echo "$output" | grep -q "Posting PR Comment"; then
  pass "no PR comment attempted (no PR number in event)"
else
  fail "PR comment should not be attempted for push events"
fi

rm -f "$event_payload"

# ---------------------------------------------------------------------------
# Test 14: PR comment updates existing comment
# ---------------------------------------------------------------------------
run_test "PR comment updates existing comment when marker found"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 7}}' > "$event_payload"

# Mock curl that returns an existing comment on GET
mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
else
  # Return a comment with the marker
  echo '[{"id": 99999, "body": "<!-- lcov-coverage-check -->\nold report"}]'
fi
MOCKCURL
chmod +x "${mock_bin}/curl"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "Updated existing PR comment (ID: 99999)"; then
  pass "output confirms existing comment updated"
else
  fail "output missing update confirmation"
fi

# Verify PATCH was used (not POST)
if grep -q "\-X PATCH" "$curl_log" 2>/dev/null; then
  pass "curl used PATCH to update existing comment"
else
  fail "curl should have used PATCH"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 15: Baseline retrieval succeeds
# ---------------------------------------------------------------------------
run_test "Baseline retrieval: succeeds with valid API responses"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-test-XXXXXX")"

# Create a baseline LCOV file and zip it
mkdir -p "${tmpdir}/artifact-content"
cp "$FIXTURES_DIR/baseline.lcov.info" "${tmpdir}/artifact-content/lcov.info"
(cd "${tmpdir}/artifact-content" && zip -q "${tmpdir}/test-artifact.zip" lcov.info)

# Create event payload with PR refs
event_payload="${tmpdir}/event.json"
cat > "$event_payload" <<'JSON'
{"pull_request": {"base": {"sha": "abc123base"}, "head": {"sha": "def456head"}, "number": 42}}
JSON

# Create mock curl with counter-based dispatch
mock_bin="${tmpdir}/mock-bin"
mkdir -p "$mock_bin"
cp "${tmpdir}/test-artifact.zip" "${mock_bin}/test-artifact.zip"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
mock_dir="$(dirname "$0")"
counter_file="${mock_dir}/curl_counter"
if [[ ! -f "$counter_file" ]]; then echo 0 > "$counter_file"; fi
count=$(cat "$counter_file")
count=$((count + 1))
echo "$count" > "$counter_file"

# Parse -o argument for file download
output_file=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "-o" ]]; then
    output_file="${args[$((i+1))]}"
    break
  fi
done

case $count in
  1) printf '%s\n%s' '{"workflow_id": 12345}' '200' ;;
  2) echo '{"default_branch": "main"}' ;;
  3) echo '{"workflow_runs": [{"id": 67890}]}' ;;
  4) echo '{"artifacts": [{"name": "lcov-baseline", "expired": false, "archive_download_url": "https://example.com/artifact.zip"}]}' ;;
  5) if [[ -n "$output_file" ]]; then cp "${mock_dir}/test-artifact.zip" "$output_file"; fi ;;
esac
MOCKCURL
chmod +x "${mock_bin}/curl"

# Set up GITHUB_OUTPUT
github_output="${tmpdir}/github_output"
: > "$github_output"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_OUTPUT="$github_output" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_RUN_ID="11111" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$RETRIEVE_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q "downloaded=true" "$github_output"; then
  pass "output contains downloaded=true"
else
  fail "output missing downloaded=true"
fi

if grep -q "baseline-path=" "$github_output"; then
  baseline_path="$(grep "baseline-path=" "$github_output" | cut -d= -f2-)"
  if [[ -f "$baseline_path" ]]; then
    pass "baseline file exists at output path"
  else
    fail "baseline file does not exist at output path"
  fi
else
  fail "output missing baseline-path"
fi

if grep -q "base-ref=abc123base" "$github_output"; then
  pass "base-ref correctly detected from event payload"
else
  fail "base-ref not detected"
fi

if grep -q "head-ref=def456head" "$github_output"; then
  pass "head-ref correctly detected from event payload"
else
  fail "head-ref not detected"
fi

rm -rf "$tmpdir"

# ---------------------------------------------------------------------------
# Test 16: Baseline retrieval — no successful runs
# ---------------------------------------------------------------------------
run_test "Baseline retrieval: no successful runs on default branch"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-test-XXXXXX")"

mock_bin="${tmpdir}/mock-bin"
mkdir -p "$mock_bin"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
mock_dir="$(dirname "$0")"
counter_file="${mock_dir}/curl_counter"
if [[ ! -f "$counter_file" ]]; then echo 0 > "$counter_file"; fi
count=$(cat "$counter_file")
count=$((count + 1))
echo "$count" > "$counter_file"

case $count in
  1) printf '%s\n%s' '{"workflow_id": 12345}' '200' ;;
  2) echo '{"default_branch": "main"}' ;;
  3) echo '{"workflow_runs": []}' ;;
esac
MOCKCURL
chmod +x "${mock_bin}/curl"

github_output="${tmpdir}/github_output"
: > "$github_output"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_OUTPUT="$github_output" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_RUN_ID="11111" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$RETRIEVE_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0 (graceful fallback)"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q "downloaded=false" "$github_output"; then
  pass "output contains downloaded=false"
else
  fail "output missing downloaded=false"
fi

rm -rf "$tmpdir"

# ---------------------------------------------------------------------------
# Test 17: Baseline retrieval — artifact missing/expired
# ---------------------------------------------------------------------------
run_test "Baseline retrieval: artifact missing or expired"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-test-XXXXXX")"

mock_bin="${tmpdir}/mock-bin"
mkdir -p "$mock_bin"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
mock_dir="$(dirname "$0")"
counter_file="${mock_dir}/curl_counter"
if [[ ! -f "$counter_file" ]]; then echo 0 > "$counter_file"; fi
count=$(cat "$counter_file")
count=$((count + 1))
echo "$count" > "$counter_file"

case $count in
  1) printf '%s\n%s' '{"workflow_id": 12345}' '200' ;;
  2) echo '{"default_branch": "main"}' ;;
  3) echo '{"workflow_runs": [{"id": 67890}]}' ;;
  4) echo '{"artifacts": []}' ;;
esac
MOCKCURL
chmod +x "${mock_bin}/curl"

github_output="${tmpdir}/github_output"
: > "$github_output"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_OUTPUT="$github_output" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_RUN_ID="11111" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$RETRIEVE_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0 (graceful fallback)"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q "downloaded=false" "$github_output"; then
  pass "output contains downloaded=false"
else
  fail "output missing downloaded=false"
fi

rm -rf "$tmpdir"

# ---------------------------------------------------------------------------
# Test 18: Baseline retrieval — API error (curl failure)
# ---------------------------------------------------------------------------
run_test "Baseline retrieval: API error triggers graceful fallback"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-test-XXXXXX")"

mock_bin="${tmpdir}/mock-bin"
mkdir -p "$mock_bin"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
exit 1
MOCKCURL
chmod +x "${mock_bin}/curl"

github_output="${tmpdir}/github_output"
: > "$github_output"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_OUTPUT="$github_output" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_RUN_ID="11111" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$RETRIEVE_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0 (graceful fallback)"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q "downloaded=false" "$github_output"; then
  pass "output contains downloaded=false"
else
  fail "output missing downloaded=false"
fi

rm -rf "$tmpdir"

# ---------------------------------------------------------------------------
# Test 19: Baseline retrieval — auto-detects refs from PR event payload
# ---------------------------------------------------------------------------
run_test "Baseline retrieval: auto-detects refs from PR event payload"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-test-XXXXXX")"

# Create a baseline LCOV file and zip it
mkdir -p "${tmpdir}/artifact-content"
cp "$FIXTURES_DIR/baseline.lcov.info" "${tmpdir}/artifact-content/lcov.info"
(cd "${tmpdir}/artifact-content" && zip -q "${tmpdir}/test-artifact.zip" lcov.info)

# Create event payload with specific SHAs
event_payload="${tmpdir}/event.json"
cat > "$event_payload" <<'JSON'
{"pull_request": {"base": {"sha": "sha-base-1234"}, "head": {"sha": "sha-head-5678"}, "number": 99}}
JSON

mock_bin="${tmpdir}/mock-bin"
mkdir -p "$mock_bin"
cp "${tmpdir}/test-artifact.zip" "${mock_bin}/test-artifact.zip"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
mock_dir="$(dirname "$0")"
counter_file="${mock_dir}/curl_counter"
if [[ ! -f "$counter_file" ]]; then echo 0 > "$counter_file"; fi
count=$(cat "$counter_file")
count=$((count + 1))
echo "$count" > "$counter_file"

output_file=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "-o" ]]; then
    output_file="${args[$((i+1))]}"
    break
  fi
done

case $count in
  1) printf '%s\n%s' '{"workflow_id": 12345}' '200' ;;
  2) echo '{"default_branch": "main"}' ;;
  3) echo '{"workflow_runs": [{"id": 67890}]}' ;;
  4) echo '{"artifacts": [{"name": "lcov-baseline", "expired": false, "archive_download_url": "https://example.com/artifact.zip"}]}' ;;
  5) if [[ -n "$output_file" ]]; then cp "${mock_dir}/test-artifact.zip" "$output_file"; fi ;;
esac
MOCKCURL
chmod +x "${mock_bin}/curl"

github_output="${tmpdir}/github_output"
: > "$github_output"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_OUTPUT="$github_output" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_RUN_ID="11111" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$RETRIEVE_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q "base-ref=sha-base-1234" "$github_output"; then
  pass "base-ref detected as sha-base-1234"
else
  fail "base-ref not correctly detected"
fi

if grep -q "head-ref=sha-head-5678" "$github_output"; then
  pass "head-ref detected as sha-head-5678"
else
  fail "head-ref not correctly detected"
fi

rm -rf "$tmpdir"

# ---------------------------------------------------------------------------
# Test 20: Baseline retrieval — does not detect refs on push event
# ---------------------------------------------------------------------------
run_test "Baseline retrieval: does not detect refs on push event"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-test-XXXXXX")"

# Create a baseline LCOV file and zip it
mkdir -p "${tmpdir}/artifact-content"
cp "$FIXTURES_DIR/baseline.lcov.info" "${tmpdir}/artifact-content/lcov.info"
(cd "${tmpdir}/artifact-content" && zip -q "${tmpdir}/test-artifact.zip" lcov.info)

# Create a push event payload (no pull_request field)
event_payload="${tmpdir}/event.json"
cat > "$event_payload" <<'JSON'
{"ref": "refs/heads/main", "after": "abc123"}
JSON

mock_bin="${tmpdir}/mock-bin"
mkdir -p "$mock_bin"
cp "${tmpdir}/test-artifact.zip" "${mock_bin}/test-artifact.zip"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
mock_dir="$(dirname "$0")"
counter_file="${mock_dir}/curl_counter"
if [[ ! -f "$counter_file" ]]; then echo 0 > "$counter_file"; fi
count=$(cat "$counter_file")
count=$((count + 1))
echo "$count" > "$counter_file"

output_file=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "-o" ]]; then
    output_file="${args[$((i+1))]}"
    break
  fi
done

case $count in
  1) printf '%s\n%s' '{"workflow_id": 12345}' '200' ;;
  2) echo '{"default_branch": "main"}' ;;
  3) echo '{"workflow_runs": [{"id": 67890}]}' ;;
  4) echo '{"artifacts": [{"name": "lcov-baseline", "expired": false, "archive_download_url": "https://example.com/artifact.zip"}]}' ;;
  5) if [[ -n "$output_file" ]]; then cp "${mock_dir}/test-artifact.zip" "$output_file"; fi ;;
esac
MOCKCURL
chmod +x "${mock_bin}/curl"

github_output="${tmpdir}/github_output"
: > "$github_output"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_OUTPUT="$github_output" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_RUN_ID="11111" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$RETRIEVE_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q "downloaded=true" "$github_output"; then
  pass "baseline still downloaded on push event"
else
  fail "baseline should still be downloaded"
fi

if ! grep -q "base-ref=" "$github_output"; then
  pass "no base-ref detected (push event, no pull_request)"
else
  fail "base-ref should not be set for push events"
fi

if ! grep -q "head-ref=" "$github_output"; then
  pass "no head-ref detected (push event, no pull_request)"
else
  fail "head-ref should not be set for push events"
fi

rm -rf "$tmpdir"

# ---------------------------------------------------------------------------
# Test 21: GHES compatibility — check-coverage.sh uses GITHUB_API_URL
# ---------------------------------------------------------------------------
run_test "GHES compatibility: check-coverage.sh uses GITHUB_API_URL"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

# Create a mock curl that logs its calls
mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
else
  echo '[]'
fi
MOCKCURL
chmod +x "${mock_bin}/curl"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_API_URL="https://github.example.com/api/v3" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q "github.example.com/api/v3" "$curl_log" 2>/dev/null; then
  pass "curl used GITHUB_API_URL (GHES endpoint)"
else
  fail "curl did not use GITHUB_API_URL"
fi

if ! grep -q "api.github.com" "$curl_log" 2>/dev/null; then
  pass "curl did not use default api.github.com"
else
  fail "curl should not use api.github.com when GITHUB_API_URL is set"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 22: Non-Dart extension works (Python .py files)
# ---------------------------------------------------------------------------
run_test "Non-Dart extension: .py files detected as new"

tmpdir="$(setup_git_repo \
  "lib/src/existing.py:old" \
  "lib/src/app.py:new lib/src/utils.py:new" \
  ""
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/python-project.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/python-project.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="40" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "lib/src/app.py"; then
  pass "output mentions .py new file (app.py)"
else
  fail "output missing .py new file detection"
fi

if echo "$output" | grep -q "lib/src/utils.py"; then
  pass "output mentions .py new file (utils.py)"
else
  fail "output missing .py new file detection (utils.py)"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 23: Non-source files excluded (only extensions in LCOV are checked)
# ---------------------------------------------------------------------------
run_test "Non-source files excluded: .md not flagged when LCOV has .dart"

tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a" \
  "lib/src/new_widget.dart:new lib/README.md:docs" \
  ""
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/new-file.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="40" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if ! echo "$output" | grep -q "README.md"; then
  pass ".md file correctly excluded from new file check"
else
  fail ".md file should not appear in new file check"
fi

if echo "$output" | grep -q "new_widget.dart"; then
  pass ".dart file correctly included in new file check"
else
  fail ".dart file should appear in new file check"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 24: Multiple extensions — .ts and .tsx both checked
# ---------------------------------------------------------------------------
run_test "Multiple extensions: .ts and .tsx both detected"

tmpdir="$(setup_git_repo \
  "lib/src/old.ts:old" \
  "lib/src/app.ts:new lib/src/Component.tsx:new" \
  ""
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/multi-ext.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/multi-ext.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="40" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "lib/src/app.ts"; then
  pass ".ts file detected"
else
  fail ".ts file not detected"
fi

if echo "$output" | grep -q "lib/src/Component.tsx"; then
  pass ".tsx file detected"
else
  fail ".tsx file not detected"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 25: Changed file with non-Dart extension — ratchet check works for .py
# ---------------------------------------------------------------------------
run_test "Changed file ratchet works for .py files"

# Create a baseline with higher coverage and a current with lower coverage for app.py
py_baseline="$(mktemp "${TMPDIR:-/tmp}/py-baseline-XXXXXX")"
cat > "$py_baseline" <<'LCOV'
TN:
SF:lib/src/app.py
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

py_current="$(mktemp "${TMPDIR:-/tmp}/py-current-XXXXXX")"
cat > "$py_current" <<'LCOV'
TN:
SF:lib/src/app.py
DA:1,1
DA:2,0
DA:3,0
DA:4,0
LF:4
LH:1
end_of_record
LCOV

tmpdir="$(setup_git_repo \
  "lib/src/app.py:old" \
  "" \
  "lib/src/app.py:modified"
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$py_current" \
  INPUT_LCOV_BASE="$py_baseline" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 1 ]]; then
  pass "exit code is 1 (coverage decreased)"
else
  fail "expected exit code 1, got $exit_code"
fi

if echo "$output" | grep -q "lib/src/app.py.*coverage decreased"; then
  pass "output reports .py file coverage decrease"
else
  fail "output missing .py coverage decrease message"
fi

rm -f "$py_baseline" "$py_current"
cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 26: Baseline retrieval — HTTP 403 permission error
# ---------------------------------------------------------------------------
run_test "Baseline retrieval: HTTP 403 mentions actions:read permission"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-test-XXXXXX")"

mock_bin="${tmpdir}/mock-bin"
mkdir -p "$mock_bin"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
# Return a 403 response body and status code (simulating missing actions:read)
printf '%s\n%s' '{"message":"Resource not accessible by integration"}' '403'
MOCKCURL
chmod +x "${mock_bin}/curl"

github_output="${tmpdir}/github_output"
: > "$github_output"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_OUTPUT="$github_output" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_RUN_ID="11111" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$RETRIEVE_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0 (graceful fallback)"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q "downloaded=false" "$github_output"; then
  pass "output contains downloaded=false"
else
  fail "output missing downloaded=false"
fi

if echo "$output" | grep -q "actions: read"; then
  pass "notice message mentions 'actions: read' permission"
else
  fail "notice message should mention 'actions: read' permission"
fi

if echo "$output" | grep -q "HTTP 403"; then
  pass "notice message mentions HTTP 403"
else
  fail "notice message should mention HTTP 403"
fi

rm -rf "$tmpdir"

# ---------------------------------------------------------------------------
# Test 27: Ignore patterns — excluded files affect overall coverage
# ---------------------------------------------------------------------------
run_test "Ignore patterns: excluded files removed from overall coverage"

# with-generated.lcov.info has 4 files:
#   widget_a.dart: 4/4 (100%), widget_b.dart: 3/4 (75%),
#   widget_a.g.dart: 0/4 (0%), models/data.freezed.dart: 0/6 (0%)
# Total without filtering: 7/18 = 38.89%
# After ignoring *.g.dart and *.freezed.dart: 7/8 = 87.50%

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/with-generated.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="$(printf '%s\n%s' '*.g.dart' '*.freezed.dart')" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "87.50%"; then
  pass "overall coverage is 87.50% (generated files excluded)"
else
  fail "expected 87.50% coverage after ignoring generated files, got: $(echo "$output" | grep 'Overall:')"
fi

if echo "$output" | grep -q "widget_a.g.dart"; then
  fail "output should not mention widget_a.g.dart (it was ignored)"
else
  pass "ignored file widget_a.g.dart not in output"
fi

if echo "$output" | grep -q "data.freezed.dart"; then
  fail "output should not mention data.freezed.dart (it was ignored)"
else
  pass "ignored file data.freezed.dart not in output"
fi

# ---------------------------------------------------------------------------
# Test 28: Ignore patterns — new file matching ignore pattern is skipped
# ---------------------------------------------------------------------------
run_test "Ignore patterns: new file matching pattern is skipped"

tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a" \
  "lib/src/widget_b.dart:new lib/src/widget_a.g.dart:generated" \
  ""
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/with-generated.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_IGNORE_PATTERNS="*.g.dart" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if echo "$output" | grep -q "SKIP.*widget_a.g.dart.*ignore pattern"; then
  pass "generated new file skipped due to ignore pattern"
else
  fail "expected widget_a.g.dart to be skipped via ignore pattern"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 29: Ignore patterns — changed file matching ignore pattern is skipped
# ---------------------------------------------------------------------------
run_test "Ignore patterns: changed file matching pattern is skipped"

tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a lib/src/widget_a.g.dart:generated" \
  "" \
  "lib/src/widget_a.dart:a-modified lib/src/widget_a.g.dart:generated-modified"
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/with-generated.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="*.g.dart" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if echo "$output" | grep -q "SKIP.*widget_a.g.dart.*ignore pattern"; then
  pass "generated changed file skipped due to ignore pattern"
else
  fail "expected widget_a.g.dart to be skipped via ignore pattern"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 30: Ignore patterns — directory glob pattern
# ---------------------------------------------------------------------------
run_test "Ignore patterns: directory glob pattern excludes files"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/with-generated.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="lib/src/models/*" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if echo "$output" | grep -q "data.freezed.dart"; then
  fail "output should not mention files under lib/src/models/"
else
  pass "files under lib/src/models/ excluded by directory pattern"
fi

# Without the models dir, we have widget_a (4/4), widget_b (3/4), widget_a.g (0/4) = 7/12 = 58.33%
if echo "$output" | grep -q "58.33%"; then
  pass "overall coverage is 58.33% (models dir excluded)"
else
  fail "expected 58.33% coverage after excluding models dir, got: $(echo "$output" | grep 'Overall:')"
fi

# ---------------------------------------------------------------------------
# Test 31: Ignore patterns — empty patterns has no effect
# ---------------------------------------------------------------------------
run_test "Ignore patterns: empty patterns has no effect"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "87.50%"; then
  pass "coverage unchanged at 87.50% with empty patterns"
else
  fail "expected 87.50% coverage with empty patterns"
fi

if echo "$output" | grep -q "Ignore Patterns"; then
  fail "should not print ignore patterns header when empty"
else
  pass "no ignore patterns header when empty"
fi

# ---------------------------------------------------------------------------
# Test 32: Ignore patterns — multiple patterns with baseline comparison
# ---------------------------------------------------------------------------
run_test "Ignore patterns: multiple patterns with baseline comparison"

# Create baseline and current fixtures where generated files drag down coverage
# Baseline (with-generated): 7/18 unfiltered, but after filtering *.g.dart + *.freezed.dart: 7/8
# Current (with-generated): same fixture — coverage should match baseline
output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/with-generated.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/with-generated.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="$(printf '%s\n%s' '*.g.dart' '*.freezed.dart')" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "Coverage did not decrease"; then
  pass "filtered comparison passes correctly"
else
  fail "expected comparison pass after filtering"
fi

# ---------------------------------------------------------------------------
# Test 33: Shallow clone — fetches refs and detects new/modified files
# ---------------------------------------------------------------------------
run_test "Shallow clone: fetches refs and detects new/modified files"

# Create a bare repo, push base+head commits, then shallow-clone
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-shallow-XXXXXX")"
bare_repo="${tmpdir}/bare.git"
work_repo="${tmpdir}/work"
shallow_repo="${tmpdir}/shallow"

# Build the repo with commits
(
  git init -q --bare "$bare_repo"
  git clone -q "$bare_repo" "$work_repo"
  cd "$work_repo"
  git config user.email "test@test.com"
  git config user.name "Test"

  # Base commit with one existing file
  mkdir -p lib/src
  echo "base content" > lib/src/widget_a.dart
  git add lib/src/widget_a.dart
  git commit -q -m "base commit"
  git tag base_ref
  git push -q origin main 2>/dev/null || git push -q origin master 2>/dev/null || true
  git push -q origin base_ref

  # Head commit: add a new file, modify the existing one
  echo "new file" > lib/src/new_widget.dart
  echo "modified content" > lib/src/widget_a.dart
  git add lib/src/new_widget.dart lib/src/widget_a.dart
  git commit -q -m "head commit"
  git tag head_ref
  git push -q origin head_ref
) 2>/dev/null

# Shallow clone with depth=1 of head_ref only (simulates actions/checkout default)
git clone -q --depth=1 --branch head_ref "$bare_repo" "$shallow_repo" 2>/dev/null

# Create LCOV data that covers the new and existing file
lcov_current="$(mktemp "${TMPDIR:-/tmp}/lcov-shallow-current-XXXXXX")"
cat > "$lcov_current" <<'LCOV'
TN:
SF:lib/src/widget_a.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:lib/src/new_widget.dart
DA:1,1
DA:2,1
LF:2
LH:2
end_of_record
LCOV

lcov_baseline="$(mktemp "${TMPDIR:-/tmp}/lcov-shallow-baseline-XXXXXX")"
cat > "$lcov_baseline" <<'LCOV'
TN:
SF:lib/src/widget_a.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

output="$(
  cd "$shallow_repo" && \
  INPUT_LCOV_FILE="$lcov_current" \
  INPUT_LCOV_BASE="$lcov_baseline" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="50" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
  echo "  Output: $output"
fi

if echo "$output" | grep -q "new_widget.dart"; then
  pass "new file detected in shallow clone"
else
  fail "new file not detected in shallow clone"
  echo "  Output: $output"
fi

if ! echo "$output" | grep -q "No new files detected"; then
  pass "does not say 'No new files detected'"
else
  fail "incorrectly says 'No new files detected'"
fi

if ! echo "$output" | grep -q "::warning::"; then
  pass "no warning emitted (refs fetched successfully)"
else
  fail "unexpected warning emitted"
fi

rm -f "$lcov_current" "$lcov_baseline"
rm -rf "$tmpdir"

# ---------------------------------------------------------------------------
# Test 34: Warning emitted when git diff fails (unreachable refs)
# ---------------------------------------------------------------------------
run_test "Warning emitted when git diff fails with unreachable refs"

# Create a simple repo with no remote — fetch will fail, refs don't exist
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-warn-XXXXXX")"
(
  cd "$tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p lib/src
  echo "content" > lib/src/widget.dart
  git add lib/src/widget.dart
  git commit -q -m "initial"
)

lcov_file="$(mktemp "${TMPDIR:-/tmp}/lcov-warn-XXXXXX")"
cat > "$lcov_file" <<'LCOV'
TN:
SF:lib/src/widget.dart
DA:1,1
LF:1
LH:1
end_of_record
LCOV

lcov_base="$(mktemp "${TMPDIR:-/tmp}/lcov-warn-base-XXXXXX")"
cat > "$lcov_base" <<'LCOV'
TN:
SF:lib/src/widget.dart
DA:1,1
LF:1
LH:1
end_of_record
LCOV

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$lcov_file" \
  INPUT_LCOV_BASE="$lcov_base" \
  INPUT_BASE_REF="nonexistent-sha-abc123" \
  INPUT_HEAD_REF="nonexistent-sha-def456" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0 (action does not crash)"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "::warning::Failed to detect new files"; then
  pass "warning emitted for failed new file detection"
else
  fail "expected warning about failed new file detection"
  echo "  Output: $output"
fi

if echo "$output" | grep -q "::warning::Failed to detect modified files"; then
  pass "warning emitted for failed modified file detection"
else
  fail "expected warning about failed modified file detection"
  echo "  Output: $output"
fi

rm -f "$lcov_file" "$lcov_base"
rm -rf "$tmpdir"

# ---------------------------------------------------------------------------
# Test 35: Multi-path — new files detected across both path prefixes
# ---------------------------------------------------------------------------
run_test "Multi-path: new files detected across both path prefixes"

tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a src/app.dart:a" \
  "lib/src/new_widget.dart:new src/new_app.dart:new" \
  ""
)"

mp_lcov="$(mktemp "${TMPDIR:-/tmp}/mp-lcov-XXXXXX")"
cat > "$mp_lcov" <<'LCOV'
TN:
SF:lib/src/widget_a.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:lib/src/new_widget.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:src/app.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:src/new_app.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

mp_base="$(mktemp "${TMPDIR:-/tmp}/mp-base-XXXXXX")"
cat > "$mp_base" <<'LCOV'
TN:
SF:lib/src/widget_a.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:src/app.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$mp_lcov" \
  INPUT_LCOV_BASE="$mp_base" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="40" \
  INPUT_PATH="$(printf '%s\n%s' 'lib/' 'src/')" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "lib/src/new_widget.dart"; then
  pass "new file under lib/ detected"
else
  fail "new file under lib/ not detected"
fi

if echo "$output" | grep -q "src/new_app.dart"; then
  pass "new file under src/ detected"
else
  fail "new file under src/ not detected"
fi

rm -f "$mp_lcov" "$mp_base"
cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 36: Multi-path — changed file ratchet works across both paths
# ---------------------------------------------------------------------------
run_test "Multi-path: changed file ratchet works across both path prefixes"

tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a src/app.dart:a" \
  "" \
  "lib/src/widget_a.dart:modified src/app.dart:modified"
)"

mp_base="$(mktemp "${TMPDIR:-/tmp}/mp-base-XXXXXX")"
cat > "$mp_base" <<'LCOV'
TN:
SF:lib/src/widget_a.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:src/app.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

mp_cur="$(mktemp "${TMPDIR:-/tmp}/mp-cur-XXXXXX")"
cat > "$mp_cur" <<'LCOV'
TN:
SF:lib/src/widget_a.dart
DA:1,1
DA:2,0
DA:3,1
DA:4,0
LF:4
LH:2
end_of_record
TN:
SF:src/app.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$mp_cur" \
  INPUT_LCOV_BASE="$mp_base" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="$(printf '%s\n%s' 'lib/' 'src/')" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 1 ]]; then
  pass "exit code is 1 (failure due to coverage decrease)"
else
  fail "expected exit code 1, got $exit_code"
fi

if echo "$output" | grep -q "widget_a.dart.*decreased"; then
  pass "coverage decrease detected for file under lib/"
else
  fail "expected coverage decrease for lib/src/widget_a.dart"
fi

rm -f "$mp_base" "$mp_cur"
cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 37: Single path with trailing newline works (backward compat)
# ---------------------------------------------------------------------------
run_test "Single path with trailing newline works correctly"

tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a" \
  "lib/src/new_widget.dart:new" \
  ""
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/new-file.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="40" \
  INPUT_PATH="$(printf 'lib/\n')" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "new_widget.dart"; then
  pass "new file detected with trailing newline in path"
else
  fail "new file not detected"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 38: Empty path matches all files
# ---------------------------------------------------------------------------
run_test "Empty path matches all files"

tmpdir="$(setup_git_repo \
  "anywhere/file.dart:a" \
  "somewhere/new_file.dart:new" \
  ""
)"

ep_lcov="$(mktemp "${TMPDIR:-/tmp}/ep-lcov-XXXXXX")"
cat > "$ep_lcov" <<'LCOV'
TN:
SF:anywhere/file.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:somewhere/new_file.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

ep_base="$(mktemp "${TMPDIR:-/tmp}/ep-base-XXXXXX")"
cat > "$ep_base" <<'LCOV'
TN:
SF:anywhere/file.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$ep_lcov" \
  INPUT_LCOV_BASE="$ep_base" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="40" \
  INPUT_PATH="" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "somewhere/new_file.dart"; then
  pass "file outside any prefix detected with empty path"
else
  fail "expected new file to be detected with empty path"
fi

rm -f "$ep_lcov" "$ep_base"
cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 39: Empty path with no LCOV extensions matches all files
# ---------------------------------------------------------------------------
run_test "Empty path with no LCOV extensions matches all files"

tmpdir="$(setup_git_repo \
  "anywhere/file:a" \
  "somewhere/newfile:new" \
  ""
)"

# LCOV with extensionless source files — extract_lcov_extensions returns nothing
ep2_lcov="$(mktemp "${TMPDIR:-/tmp}/ep2-lcov-XXXXXX")"
cat > "$ep2_lcov" <<'LCOV'
TN:
SF:anywhere/file
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:somewhere/newfile
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

ep2_base="$(mktemp "${TMPDIR:-/tmp}/ep2-base-XXXXXX")"
cat > "$ep2_base" <<'LCOV'
TN:
SF:anywhere/file
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$ep2_lcov" \
  INPUT_LCOV_BASE="$ep2_base" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="40" \
  INPUT_PATH="" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "somewhere/newfile"; then
  pass "extensionless file detected with empty path"
else
  fail "expected new file to be detected with empty path and no extensions"
fi

rm -f "$ep2_lcov" "$ep2_base"
cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 40: Path prefixes are displayed in output
# ---------------------------------------------------------------------------
run_test "Path prefixes are displayed in output"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="$(printf '%s\n%s' 'lib/' 'src/')" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if echo "$output" | grep -q "Path Prefixes"; then
  pass "output contains 'Path Prefixes' header"
else
  fail "output missing 'Path Prefixes' header"
fi

if echo "$output" | grep -q "lib/"; then
  pass "output shows lib/ prefix"
else
  fail "output missing lib/ prefix"
fi

if echo "$output" | grep -q "src/"; then
  pass "output shows src/ prefix"
else
  fail "output missing src/ prefix"
fi

# ---------------------------------------------------------------------------
# Test 41: Coverage label — summary-only heading includes label
# ---------------------------------------------------------------------------
run_test "Coverage label: summary-only heading includes label"

step_summary="$(mktemp "${TMPDIR:-/tmp}/step-summary-XXXXXX")"

output="$(
  GITHUB_STEP_SUMMARY="$step_summary" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_COVERAGE_LABEL="backend" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q "Coverage Summary — backend" "$step_summary" 2>/dev/null; then
  pass "step summary contains 'Coverage Summary — backend'"
else
  fail "step summary missing 'Coverage Summary — backend'"
fi

rm -f "$step_summary"

# ---------------------------------------------------------------------------
# Test 42: Coverage label — comparison heading includes label
# ---------------------------------------------------------------------------
run_test "Coverage label: comparison heading includes label"

step_summary="$(mktemp "${TMPDIR:-/tmp}/step-summary-XXXXXX")"

output="$(
  GITHUB_STEP_SUMMARY="$step_summary" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_COVERAGE_LABEL="go" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q "Coverage Report — go" "$step_summary" 2>/dev/null; then
  pass "step summary contains 'Coverage Report — go'"
else
  fail "step summary missing 'Coverage Report — go'"
fi

rm -f "$step_summary"

# ---------------------------------------------------------------------------
# Test 43: Coverage label — no label produces original headings
# ---------------------------------------------------------------------------
run_test "Coverage label: no label produces original headings (backwards compat)"

step_summary="$(mktemp "${TMPDIR:-/tmp}/step-summary-XXXXXX")"

output="$(
  GITHUB_STEP_SUMMARY="$step_summary" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_COVERAGE_LABEL="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q "Coverage Summary" "$step_summary" 2>/dev/null; then
  pass "step summary contains 'Coverage Summary'"
else
  fail "step summary missing 'Coverage Summary'"
fi

if grep -q "Coverage Summary —" "$step_summary" 2>/dev/null; then
  fail "step summary should NOT contain 'Coverage Summary —' when no label is set"
else
  pass "step summary does not contain 'Coverage Summary —'"
fi

rm -f "$step_summary"

# ---------------------------------------------------------------------------
# Test 44: Coverage label — comment marker includes label
# ---------------------------------------------------------------------------
run_test "Coverage label: comment marker includes label"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
else
  echo '[]'
fi
MOCKCURL
chmod +x "${mock_bin}/curl"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_JOB="test-job" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_COVERAGE_LABEL="go" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q 'lcov-coverage-check:go' "$curl_log" 2>/dev/null; then
  pass "curl log contains labeled marker 'lcov-coverage-check:go'"
else
  fail "curl log missing labeled marker"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 45: Coverage label — different labels produce different markers
# ---------------------------------------------------------------------------
run_test "Coverage label: different labels produce different markers"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

# Run with label "go"
mock_bin_go="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log_go="${mock_bin_go}/curl.log"
cat > "${mock_bin_go}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
else
  echo '[]'
fi
MOCKCURL
chmod +x "${mock_bin_go}/curl"

PATH="${mock_bin_go}:${PATH}" \
GITHUB_EVENT_PATH="$event_payload" \
GITHUB_REPOSITORY="owner/repo" \
GITHUB_JOB="test-job" \
INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
INPUT_BASE_REF="" \
INPUT_HEAD_REF="HEAD" \
INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
INPUT_PATH="lib/" \
INPUT_CHANGED_FILE_NO_DECREASE="true" \
INPUT_IGNORE_PATTERNS="" \
INPUT_COVERAGE_LABEL="go" \
INPUT_GITHUB_TOKEN="fake-token" \
bash "$CHECK_SCRIPT" > /dev/null 2>&1 || true

# Run with label "frontend"
mock_bin_fe="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log_fe="${mock_bin_fe}/curl.log"
cat > "${mock_bin_fe}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
else
  echo '[]'
fi
MOCKCURL
chmod +x "${mock_bin_fe}/curl"

PATH="${mock_bin_fe}:${PATH}" \
GITHUB_EVENT_PATH="$event_payload" \
GITHUB_REPOSITORY="owner/repo" \
GITHUB_JOB="test-job" \
INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
INPUT_BASE_REF="" \
INPUT_HEAD_REF="HEAD" \
INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
INPUT_PATH="lib/" \
INPUT_CHANGED_FILE_NO_DECREASE="true" \
INPUT_IGNORE_PATTERNS="" \
INPUT_COVERAGE_LABEL="frontend" \
INPUT_GITHUB_TOKEN="fake-token" \
bash "$CHECK_SCRIPT" > /dev/null 2>&1 || true

if grep -q 'lcov-coverage-check:go' "$curl_log_go" 2>/dev/null; then
  pass "first run uses marker 'lcov-coverage-check:go'"
else
  fail "first run missing marker 'lcov-coverage-check:go'"
fi

if grep -q 'lcov-coverage-check:frontend' "$curl_log_fe" 2>/dev/null; then
  pass "second run uses marker 'lcov-coverage-check:frontend'"
else
  fail "second run missing marker 'lcov-coverage-check:frontend'"
fi

if ! grep -q 'lcov-coverage-check:frontend' "$curl_log_go" 2>/dev/null; then
  pass "first run does NOT contain 'frontend' marker"
else
  fail "first run should not contain 'frontend' marker"
fi

if ! grep -q 'lcov-coverage-check:go' "$curl_log_fe" 2>/dev/null; then
  pass "second run does NOT contain 'go' marker"
else
  fail "second run should not contain 'go' marker"
fi

rm -f "$event_payload"
rm -rf "$mock_bin_go" "$mock_bin_fe"

# ---------------------------------------------------------------------------
# Test 46: Coverage label — label is sanitized
# ---------------------------------------------------------------------------
run_test "Coverage label: label is sanitized"

step_summary="$(mktemp "${TMPDIR:-/tmp}/step-summary-XXXXXX")"

output="$(
  GITHUB_STEP_SUMMARY="$step_summary" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_COVERAGE_LABEL="My Frontend!!" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q "Coverage Summary — my-frontend" "$step_summary" 2>/dev/null; then
  pass "step summary contains sanitized label 'my-frontend'"
else
  fail "step summary missing sanitized label 'Coverage Summary — my-frontend'"
fi

if grep -q "My Frontend" "$step_summary" 2>/dev/null; then
  fail "step summary should NOT contain unsanitized label 'My Frontend'"
else
  pass "step summary does not contain unsanitized label"
fi

rm -f "$step_summary"

# ---------------------------------------------------------------------------
# Test 47: Coverage label — retrieve-baseline uses labeled artifact name
# ---------------------------------------------------------------------------
run_test "Coverage label: retrieve-baseline uses labeled artifact name"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-test-XXXXXX")"

# Create a baseline LCOV file and zip it
mkdir -p "${tmpdir}/artifact-content"
cp "$FIXTURES_DIR/baseline.lcov.info" "${tmpdir}/artifact-content/lcov.info"
(cd "${tmpdir}/artifact-content" && zip -q "${tmpdir}/test-artifact.zip" lcov.info)

# Create event payload with PR refs
event_payload="${tmpdir}/event.json"
cat > "$event_payload" <<'JSON'
{"pull_request": {"base": {"sha": "abc123base"}, "head": {"sha": "def456head"}, "number": 42}}
JSON

# Create mock curl with counter-based dispatch
mock_bin="${tmpdir}/mock-bin"
mkdir -p "$mock_bin"
cp "${tmpdir}/test-artifact.zip" "${mock_bin}/test-artifact.zip"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
mock_dir="$(dirname "$0")"
counter_file="${mock_dir}/curl_counter"
if [[ ! -f "$counter_file" ]]; then echo 0 > "$counter_file"; fi
count=$(cat "$counter_file")
count=$((count + 1))
echo "$count" > "$counter_file"

# Log all calls for debugging
echo "CALL $count: $@" >> "${mock_dir}/curl.log"

# Parse -o argument for file download
output_file=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "-o" ]]; then
    output_file="${args[$((i+1))]}"
    break
  fi
done

case $count in
  1) printf '%s\n%s' '{"workflow_id": 12345}' '200' ;;
  2) echo '{"default_branch": "main"}' ;;
  3) echo '{"workflow_runs": [{"id": 67890}]}' ;;
  4) echo '{"artifacts": [{"name": "lcov-baseline-go", "expired": false, "archive_download_url": "https://example.com/artifact.zip"}]}' ;;
  5) if [[ -n "$output_file" ]]; then cp "${mock_dir}/test-artifact.zip" "$output_file"; fi ;;
esac
MOCKCURL
chmod +x "${mock_bin}/curl"

# Set up GITHUB_OUTPUT
github_output="${tmpdir}/github_output"
: > "$github_output"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_OUTPUT="$github_output" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_RUN_ID="11111" \
  INPUT_GITHUB_TOKEN="fake-token" \
  INPUT_COVERAGE_LABEL="go" \
  bash "$RETRIEVE_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q "downloaded=true" "$github_output"; then
  pass "output contains downloaded=true"
else
  fail "output missing downloaded=true"
fi

# The mock only returns an artifact named "lcov-baseline-go". Since
# downloaded=true, the script must have used the labeled artifact name.
# Also verify a non-labeled name was NOT echoed in the notice path.
if echo "$output" | grep -q "No lcov-baseline artifact"; then
  fail "retrieve script used unlabeled artifact name instead of 'lcov-baseline-go'"
else
  pass "retrieve script used labeled artifact name (downloaded=true confirms match)"
fi

rm -rf "$tmpdir"

# ---------------------------------------------------------------------------
# Test 48: Collision detection — labeled run finds unlabeled comment
# ---------------------------------------------------------------------------
run_test "Collision detection: labeled run finds unlabeled comment"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"

# Create comments.json: an unlabeled comment exists but no labeled one for "go"
cat > "${mock_bin}/comments.json" <<'COMMENTS'
[{"id": 100, "body": "<!-- lcov-coverage-check -->\nold unlabeled report"}]
COMMENTS

cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
else
  cat "$(dirname "$0")/comments.json"
fi
MOCKCURL
chmod +x "${mock_bin}/curl"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_JOB="test-job" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_COVERAGE_LABEL="go" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

# The POST body should contain the warning about another check without coverage-label
if grep -q 'coverage-label' "$curl_log" 2>/dev/null && grep -q 'without' "$curl_log" 2>/dev/null; then
  pass "curl log contains collision warning about unlabeled check"
else
  fail "curl log missing collision warning about unlabeled check"
fi

# Since no existing labeled comment was found, it should POST (not PATCH)
if grep -q '\-X POST' "$curl_log" 2>/dev/null; then
  pass "curl used POST to create new labeled comment"
else
  fail "curl should have used POST (no existing labeled comment)"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 49: Collision detection — unlabeled run finds labeled comment
# ---------------------------------------------------------------------------
run_test "Collision detection: unlabeled run finds labeled comment"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"

# Create comments.json: a labeled comment exists
cat > "${mock_bin}/comments.json" <<'COMMENTS'
[{"id": 200, "body": "<!-- lcov-coverage-check:go -->\nold labeled report"}]
COMMENTS

cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
else
  cat "$(dirname "$0")/comments.json"
fi
MOCKCURL
chmod +x "${mock_bin}/curl"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_JOB="test-job" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_COVERAGE_LABEL="" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

# The POST body should contain warning about other checks using coverage-label
if grep -q 'coverage-label' "$curl_log" 2>/dev/null && grep -q 'collisions' "$curl_log" 2>/dev/null; then
  pass "curl log contains collision warning about labeled checks"
else
  fail "curl log missing collision warning about labeled checks"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 50: Collision detection — unlabeled overwrites different source
# ---------------------------------------------------------------------------
run_test "Collision detection: unlabeled overwrites different source"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"

# Create comments.json: an unlabeled comment from a different source
cat > "${mock_bin}/comments.json" <<COMMENTS
[{"id": 300, "body": "<!-- lcov-coverage-check -->\n<!-- lcov-coverage-source:job-a:other-file.lcov -->\nold report from different source"}]
COMMENTS

cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
else
  cat "$(dirname "$0")/comments.json"
fi
MOCKCURL
chmod +x "${mock_bin}/curl"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_JOB="job-b" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_COVERAGE_LABEL="" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

# The PATCH body should contain overwrite warning
if grep -q 'overwritten' "$curl_log" 2>/dev/null; then
  pass "curl log contains overwrite warning"
else
  fail "curl log missing overwrite warning"
fi

# Should use PATCH (updating existing comment)
if grep -q '\-X PATCH' "$curl_log" 2>/dev/null; then
  pass "curl used PATCH to update existing comment"
else
  fail "curl should have used PATCH"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 51: No collision — same source updates itself
# ---------------------------------------------------------------------------
run_test "No collision: same source updates itself without warning"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"

# Create comments.json: an unlabeled comment from the same source
cat > "${mock_bin}/comments.json" <<COMMENTS
[{"id": 400, "body": "<!-- lcov-coverage-check -->\n<!-- lcov-coverage-source:test-job:${FIXTURES_DIR}/current.lcov.info -->\nold report from same source"}]
COMMENTS

cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
else
  cat "$(dirname "$0")/comments.json"
fi
MOCKCURL
chmod +x "${mock_bin}/curl"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_JOB="test-job" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_COVERAGE_LABEL="" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

# Should use PATCH (updating existing comment)
if grep -q '\-X PATCH' "$curl_log" 2>/dev/null; then
  pass "curl used PATCH to update existing comment"
else
  fail "curl should have used PATCH"
fi

# Should NOT contain any collision warning text
if grep -q 'Warning' "$curl_log" 2>/dev/null; then
  fail "curl log should NOT contain any warning (same source updating itself)"
else
  pass "no collision warning in curl log (same source)"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 52: No false collision when ignore patterns rewrite LCOV path
# ---------------------------------------------------------------------------
run_test "No false collision: ignore patterns don't change source identity"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"

# Existing comment uses the original LCOV file path (not a temp filtered path)
cat > "${mock_bin}/comments.json" <<COMMENTS
[{"id": 500, "body": "<!-- lcov-coverage-check -->\n<!-- lcov-coverage-source:test-job:${FIXTURES_DIR}/current.lcov.info -->\nold report"}]
COMMENTS

cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
else
  cat "$(dirname "$0")/comments.json"
fi
MOCKCURL
chmod +x "${mock_bin}/curl"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_JOB="test-job" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="*.g.dart" \
  INPUT_COVERAGE_LABEL="" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

# Source tag should use original path, not temp filtered path — no false collision
if grep -q 'Warning' "$curl_log" 2>/dev/null; then
  fail "false collision warning triggered (source tag used filtered temp path instead of original)"
else
  pass "no false collision warning when ignore patterns are active"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 53: Invalid new-file-minimum-coverage is rejected
# ---------------------------------------------------------------------------
run_test "Invalid new-file-minimum-coverage: non-numeric value rejected"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="abc" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -ne 0 ]]; then
  pass "exit code is non-zero for invalid threshold"
else
  fail "expected non-zero exit code for invalid threshold, got 0"
fi

if echo "$output" | grep -q "new-file-minimum-coverage must be a number"; then
  pass "output contains validation error message"
else
  fail "output missing validation error message"
fi

# ---------------------------------------------------------------------------
# Test 54: Out-of-range new-file-minimum-coverage is rejected
# ---------------------------------------------------------------------------
run_test "Invalid new-file-minimum-coverage: value > 100 rejected"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="150" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -ne 0 ]]; then
  pass "exit code is non-zero for out-of-range threshold"
else
  fail "expected non-zero exit code for threshold > 100, got 0"
fi

if echo "$output" | grep -q "between 0 and 100"; then
  pass "output mentions valid range"
else
  fail "output missing range error message"
fi

# ---------------------------------------------------------------------------
# Test 55: Valid decimal new-file-minimum-coverage is accepted
# ---------------------------------------------------------------------------
run_test "Valid decimal new-file-minimum-coverage: accepted"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="75.5" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0 for valid decimal threshold"
else
  fail "expected exit code 0, got $exit_code"
fi

# ---------------------------------------------------------------------------
# Test 56: Source tag sanitizes HTML comment sequences
# ---------------------------------------------------------------------------
run_test "Source tag: double-dash in GITHUB_JOB is sanitized"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
else
  echo '[]'
fi
MOCKCURL
chmod +x "${mock_bin}/curl"

# Use a job name with double-dashes (which would break HTML comments if unsanitized)
output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_JOB="ci--build--job" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_COVERAGE_LABEL="" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

# The source tag should have double-dashes collapsed to single-dashes
if grep -q 'lcov-coverage-source:ci-build-job:' "$curl_log" 2>/dev/null; then
  pass "source tag has double-dashes sanitized to single-dashes"
else
  if grep -q 'lcov-coverage-source:ci--build--job:' "$curl_log" 2>/dev/null; then
    fail "source tag still contains unsanitized double-dashes"
  else
    fail "source tag not found in curl log"
  fi
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo "Tests run:    ${TESTS_RUN}"
echo "Tests passed: ${TESTS_PASSED}"
echo "Tests failed: ${TESTS_FAILED}"
echo "============================================"

if [[ $TESTS_FAILED -gt 0 ]]; then
  echo -e "${RED}SOME TESTS FAILED${NC}"
  exit 1
else
  echo -e "${GREEN}ALL TESTS PASSED${NC}"
  exit 0
fi

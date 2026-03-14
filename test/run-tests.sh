#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# run-tests.sh — Test suite for check-coverage.sh
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK_SCRIPT="$PROJECT_DIR/scripts/check-coverage.sh"
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
  INPUT_NEW_FILE_PATH_PREFIX="lib/" \
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
  INPUT_NEW_FILE_PATH_PREFIX="lib/" \
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
  INPUT_NEW_FILE_PATH_PREFIX="lib/" \
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
  INPUT_NEW_FILE_PATH_PREFIX="lib/" \
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
  INPUT_NEW_FILE_PATH_PREFIX="lib/" \
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
  INPUT_NEW_FILE_PATH_PREFIX="lib/" \
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
  INPUT_NEW_FILE_PATH_PREFIX="lib/" \
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
  INPUT_NEW_FILE_PATH_PREFIX="lib/" \
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
  INPUT_NEW_FILE_PATH_PREFIX="lib/" \
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
  INPUT_NEW_FILE_PATH_PREFIX="lib/" \
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
  INPUT_NEW_FILE_PATH_PREFIX="lib/" \
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
  GITHUB_REPOSITORY="owner/repo" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_NEW_FILE_PATH_PREFIX="lib/" \
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
  INPUT_NEW_FILE_PATH_PREFIX="lib/" \
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
  INPUT_NEW_FILE_PATH_PREFIX="lib/" \
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

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

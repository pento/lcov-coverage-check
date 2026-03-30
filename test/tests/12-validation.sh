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

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

# Verify the comment body uses section markers (default section for unlabeled runs)
if grep -q 'lcov-section:default' "$curl_log" 2>/dev/null; then
  pass "comment body contains section marker for default"
else
  fail "comment body missing section marker 'lcov-section:default'"
fi

if grep -q 'lcov-section-end:default' "$curl_log" 2>/dev/null; then
  pass "comment body contains section end marker for default"
else
  fail "comment body missing section end marker 'lcov-section-end:default'"
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
# Test 14: PR comment updates existing consolidated comment
# ---------------------------------------------------------------------------
run_test "PR comment updates existing comment when marker found"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 7}}' > "$event_payload"

# Mock curl that returns an existing consolidated comment on GET,
# and returns the updated body on verify GET
mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
elif echo "$@" | grep -q "issues/comments/99999"; then
  # Verify GET after PATCH — return body with the default section
  printf '{"body": "<!-- lcov-coverage-check -->\\n<!-- lcov-section:default -->\\nreport\\n<!-- lcov-section-end:default -->"}'
else
  # List comments — return existing consolidated comment with a "go" section
  echo '[{"id": 99999, "body": "<!-- lcov-coverage-check -->\n<!-- lcov-section:go -->\n<!-- lcov-section-source:go-job:go.lcov -->\n## Coverage Report — go\n<!-- lcov-section-end:go -->"}]'
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

# Verify the PATCH body contains both the existing "go" section and the new "default" section
if grep -q 'lcov-section:go' "$curl_log" 2>/dev/null && grep -q 'lcov-section:default' "$curl_log" 2>/dev/null; then
  pass "PATCH body contains both 'go' and 'default' sections"
else
  fail "PATCH body should contain both existing 'go' and new 'default' sections"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

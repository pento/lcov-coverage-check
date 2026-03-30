# ---------------------------------------------------------------------------
# Test 57: Pagination finds comment on second page
# ---------------------------------------------------------------------------
run_test "Pagination: finds existing comment on second page"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"

cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
mock_dir="$(dirname "$0")"
echo "$@" >> "${mock_dir}/curl.log"

# Parse -D argument for header dump file
header_file=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "-D" ]]; then
    header_file="${args[$((i+1))]}"
    break
  fi
done

if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
elif echo "$@" | grep -q "issues/comments/88888" && ! echo "$@" | grep -q "\-D"; then
  # Verify GET for specific comment (no -D flag = not a list request)
  printf '{"body": "<!-- lcov-coverage-check -->\\n<!-- lcov-section:default -->\\nreport\\n<!-- lcov-section-end:default -->"}'
elif echo "$@" | grep -q "page=2"; then
  # Page 2: comment with the marker (consolidated format with section)
  if [[ -n "$header_file" ]]; then
    printf 'HTTP/1.1 200 OK\r\n\r\n' > "$header_file"
  fi
  echo '[{"id": 88888, "body": "<!-- lcov-coverage-check -->\n<!-- lcov-section:default -->\n<!-- lcov-section-source:old-job:old.lcov -->\nold report from page 2\n<!-- lcov-section-end:default -->"}]'
else
  # Page 1: unrelated comment, with Link header indicating more pages
  if [[ -n "$header_file" ]]; then
    printf 'HTTP/1.1 200 OK\r\nLink: <https://api.github.com/next>; rel="next"\r\n\r\n' > "$header_file"
  fi
  echo '[{"id": 100, "body": "Just a regular comment"}]'
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

if echo "$output" | grep -q "Updated existing PR comment (ID: 88888)"; then
  pass "found and updated comment from page 2"
else
  fail "output missing update confirmation for page-2 comment"
fi

if grep -q "page=2" "$curl_log" 2>/dev/null; then
  pass "curl fetched page 2"
else
  fail "curl did not fetch page 2"
fi

if grep -q '\-X PATCH' "$curl_log" 2>/dev/null; then
  pass "curl used PATCH (not POST) to update existing comment"
else
  fail "curl should have used PATCH"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 58: Pagination handles API error mid-pagination
# ---------------------------------------------------------------------------
run_test "Pagination: handles API error on second page gracefully"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"

cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
mock_dir="$(dirname "$0")"
echo "$@" >> "${mock_dir}/curl.log"

# Parse -D argument for header dump file
header_file=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "-D" ]]; then
    header_file="${args[$((i+1))]}"
    break
  fi
done

if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
elif echo "$@" | grep -q "page=2"; then
  # Page 2: API error (non-array response)
  if [[ -n "$header_file" ]]; then
    printf 'HTTP/1.1 403 Forbidden\r\n\r\n' > "$header_file"
  fi
  echo '{"message": "API rate limit exceeded"}'
else
  # Page 1: empty array, with Link header indicating more pages
  if [[ -n "$header_file" ]]; then
    printf 'HTTP/1.1 200 OK\r\nLink: <https://api.github.com/next>; rel="next"\r\n\r\n' > "$header_file"
  fi
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
  INPUT_COVERAGE_LABEL="" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0 (graceful degradation)"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "Created new PR comment"; then
  pass "created new comment after API error (no existing marker found)"
else
  fail "output missing 'Created new PR comment'"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 59: Labeled run adds section to existing consolidated comment across pages
# ---------------------------------------------------------------------------
run_test "Pagination: labeled run merges section into comment found on later page"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"

cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
mock_dir="$(dirname "$0")"
echo "$@" >> "${mock_dir}/curl.log"

# Parse -D argument for header dump file
header_file=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "-D" ]]; then
    header_file="${args[$((i+1))]}"
    break
  fi
done

if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
elif echo "$@" | grep -q "issues/comments/100" && ! echo "$@" | grep -q "\-D"; then
  # Verify GET — return body with both sections
  printf '{"body": "<!-- lcov-coverage-check -->\\n<!-- lcov-section:default -->\\nold report\\n<!-- lcov-section-end:default -->\\n<!-- lcov-section:go -->\\ngo report\\n<!-- lcov-section-end:go -->"}'
elif echo "$@" | grep -q "page=2"; then
  # Page 2: empty
  if [[ -n "$header_file" ]]; then
    printf 'HTTP/1.1 200 OK\r\n\r\n' > "$header_file"
  fi
  echo '[]'
else
  # Page 1: consolidated comment with existing default section, plus Link header
  if [[ -n "$header_file" ]]; then
    printf 'HTTP/1.1 200 OK\r\nLink: <https://api.github.com/next>; rel="next"\r\n\r\n' > "$header_file"
  fi
  echo '[{"id": 100, "body": "<!-- lcov-coverage-check -->\n<!-- lcov-section:default -->\n<!-- lcov-section-source:job-a:file.lcov -->\nold report\n<!-- lcov-section-end:default -->"}]'
fi
MOCKCURL
chmod +x "${mock_bin}/curl"

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_JOB="go-job" \
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

# Should PATCH the existing consolidated comment with both sections
if grep -q '\-X PATCH' "$curl_log" 2>/dev/null; then
  pass "curl used PATCH to update existing consolidated comment"
else
  fail "curl should have used PATCH"
fi

if grep -q 'lcov-section:default' "$curl_log" 2>/dev/null && grep -q 'lcov-section:go' "$curl_log" 2>/dev/null; then
  pass "PATCH body contains both 'default' and 'go' sections"
else
  fail "PATCH body should contain both existing 'default' and new 'go' sections"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

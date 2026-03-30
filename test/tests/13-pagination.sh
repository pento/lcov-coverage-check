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
counter_file="${mock_dir}/curl_counter"
if [[ ! -f "$counter_file" ]]; then echo 0 > "$counter_file"; fi
count=$(cat "$counter_file")
count=$((count + 1))
echo "$count" > "$counter_file"
echo "CALL $count: $@" >> "${mock_dir}/curl.log"

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
  # Page 2: comment with the marker
  if [[ -n "$header_file" ]]; then
    printf 'HTTP/1.1 200 OK\r\n\r\n' > "$header_file"
  fi
  echo '[{"id": 88888, "body": "<!-- lcov-coverage-check -->\nold report from page 2"}]'
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
counter_file="${mock_dir}/curl_counter"
if [[ ! -f "$counter_file" ]]; then echo 0 > "$counter_file"; fi
count=$(cat "$counter_file")
count=$((count + 1))
echo "$count" > "$counter_file"
echo "CALL $count: $@" >> "${mock_dir}/curl.log"

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
# Test 59: Collision detection works across paginated pages
# ---------------------------------------------------------------------------
run_test "Pagination: collision detection finds unlabeled comment across pages"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"

cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
mock_dir="$(dirname "$0")"
counter_file="${mock_dir}/curl_counter"
if [[ ! -f "$counter_file" ]]; then echo 0 > "$counter_file"; fi
count=$(cat "$counter_file")
count=$((count + 1))
echo "$count" > "$counter_file"
echo "CALL $count: $@" >> "${mock_dir}/curl.log"

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
  # Page 2: empty
  if [[ -n "$header_file" ]]; then
    printf 'HTTP/1.1 200 OK\r\n\r\n' > "$header_file"
  fi
  echo '[]'
else
  # Page 1: unlabeled coverage comment, with Link header
  if [[ -n "$header_file" ]]; then
    printf 'HTTP/1.1 200 OK\r\nLink: <https://api.github.com/next>; rel="next"\r\n\r\n' > "$header_file"
  fi
  echo '[{"id": 100, "body": "<!-- lcov-coverage-check -->\nold unlabeled report"}]'
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

# Collision warning should be present (unlabeled comment found while running labeled check)
if grep -q 'coverage-label' "$curl_log" 2>/dev/null && grep -q 'without' "$curl_log" 2>/dev/null; then
  pass "collision warning about unlabeled check detected across pages"
else
  fail "curl log missing collision warning about unlabeled check"
fi

# Should POST (not PATCH) since no labeled comment exists
if grep -q '\-X POST' "$curl_log" 2>/dev/null; then
  pass "curl used POST to create new labeled comment"
else
  fail "curl should have used POST (no existing labeled comment)"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

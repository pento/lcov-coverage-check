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

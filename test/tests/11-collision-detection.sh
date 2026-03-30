# ---------------------------------------------------------------------------
# Test 48: Section added to existing comment preserving other sections
# ---------------------------------------------------------------------------
run_test "Section consolidation: new section added alongside existing section"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"

# Existing comment has a "go" section; we're running with label "frontend"
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
elif echo "$@" | grep -q "issues/comments/100"; then
  # Verify GET — return body with both sections so retry check passes
  printf '{"body": "<!-- lcov-coverage-check -->\\n<!-- lcov-section:frontend -->\\nfrontend report\\n<!-- lcov-section-end:frontend -->\\n<!-- lcov-section:go -->\\ngo report\\n<!-- lcov-section-end:go -->"}'
else
  cat "$(dirname "$0")/comments.json"
fi
MOCKCURL
chmod +x "${mock_bin}/curl"

cat > "${mock_bin}/comments.json" <<'COMMENTS'
[{"id": 100, "body": "<!-- lcov-coverage-check -->\n<!-- lcov-section:go -->\n<!-- lcov-section-source:go-job:go.lcov -->\n## Coverage Report — go\n<!-- lcov-section-end:go -->"}]
COMMENTS

output="$(
  PATH="${mock_bin}:${PATH}" \
  GITHUB_EVENT_PATH="$event_payload" \
  GITHUB_REPOSITORY="owner/repo" \
  GITHUB_JOB="fe-job" \
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
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

# Should PATCH (existing comment found)
if grep -q '\-X PATCH' "$curl_log" 2>/dev/null; then
  pass "curl used PATCH to update existing comment"
else
  fail "curl should have used PATCH"
fi

# PATCH body must contain both sections
if grep -q 'lcov-section:go' "$curl_log" 2>/dev/null && grep -q 'lcov-section:frontend' "$curl_log" 2>/dev/null; then
  pass "PATCH body contains both 'go' and 'frontend' sections"
else
  fail "PATCH body should contain both existing 'go' and new 'frontend' sections"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 49: Section replaced/updated in existing comment
# ---------------------------------------------------------------------------
run_test "Section consolidation: existing section is replaced with updated content"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"

# Existing comment has a "go" section; we're running with label "go" again
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
elif echo "$@" | grep -q "issues/comments/200"; then
  # Verify GET — return body with updated go section
  printf '{"body": "<!-- lcov-coverage-check -->\\n<!-- lcov-section:go -->\\nnew go report\\n<!-- lcov-section-end:go -->"}'
else
  cat "$(dirname "$0")/comments.json"
fi
MOCKCURL
chmod +x "${mock_bin}/curl"

cat > "${mock_bin}/comments.json" <<'COMMENTS'
[{"id": 200, "body": "<!-- lcov-coverage-check -->\n<!-- lcov-section:go -->\n<!-- lcov-section-source:go-job:old.lcov -->\n## OLD Coverage Report — go\n<!-- lcov-section-end:go -->"}]
COMMENTS

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

if grep -q '\-X PATCH' "$curl_log" 2>/dev/null; then
  pass "curl used PATCH to update existing comment"
else
  fail "curl should have used PATCH"
fi

# Updated body should contain the new section content, not the old
if grep -q 'lcov-section:go' "$curl_log" 2>/dev/null; then
  pass "PATCH body contains 'go' section"
else
  fail "PATCH body missing 'go' section"
fi

# Old content should be replaced
if grep -q 'OLD Coverage Report' "$curl_log" 2>/dev/null; then
  fail "PATCH body still contains old section content"
else
  pass "old section content was replaced"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 50: Default section key used when no label
# ---------------------------------------------------------------------------
run_test "Section consolidation: default section key used when no label"

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
  INPUT_COVERAGE_LABEL="" \
  INPUT_GITHUB_TOKEN="fake-token" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if grep -q 'lcov-section:default' "$curl_log" 2>/dev/null; then
  pass "unlabeled run uses section key 'default'"
else
  fail "unlabeled run should use section key 'default'"
fi

if grep -q 'lcov-section-end:default' "$curl_log" 2>/dev/null; then
  pass "unlabeled run has section end marker for 'default'"
else
  fail "unlabeled run missing section end marker for 'default'"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 50b: Backwards compat — old-format comment without sections is updated
# ---------------------------------------------------------------------------
run_test "Section consolidation: old-format comment (no sections) gets section added"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"

# Existing comment has the consolidated marker but NO section markers (old format)
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X POST\|\-X PATCH"; then
  echo '{}'
elif echo "$@" | grep -q "issues/comments/300" && ! echo "$@" | grep -q "\-D"; then
  # Verify GET — return body with the new section
  printf '{"body": "<!-- lcov-coverage-check -->\\n<!-- lcov-section:default -->\\nreport\\n<!-- lcov-section-end:default -->"}'
else
  # Old-format comment: marker + content but no section markers
  echo '[{"id": 300, "body": "<!-- lcov-coverage-check -->\n<!-- lcov-coverage-source:old-job:old.lcov -->\n## Old Coverage Report\nSome old content"}]'
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

# Should PATCH (found the existing comment by marker)
if grep -q '\-X PATCH' "$curl_log" 2>/dev/null; then
  pass "curl used PATCH to update old-format comment"
else
  fail "curl should have used PATCH"
fi

# The PATCH body should include a section marker (the old body had none)
if grep -q 'lcov-section:default' "$curl_log" 2>/dev/null; then
  pass "PATCH body contains new section marker"
else
  fail "PATCH body should contain section marker for default"
fi

if echo "$output" | grep -q "Updated existing PR comment (ID: 300)"; then
  pass "output confirms existing comment updated"
else
  fail "output missing update confirmation"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Test 51: Sections are sorted (default first, then alphabetical)
# ---------------------------------------------------------------------------
run_test "Section consolidation: sections are sorted correctly"

# Source the comment library to test replace_section directly
source "$SCRIPT_DIR/../scripts/lib/comment.sh"

existing_body="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
  '<!-- lcov-coverage-check -->' \
  '<!-- lcov-section:zebra -->' \
  'zebra content' \
  '<!-- lcov-section-end:zebra -->' \
  '<!-- lcov-section:alpha -->' \
  'alpha content' \
  '<!-- lcov-section-end:alpha -->')"

new_section="$(build_section 'default' 'job:file' 'default content')"
result="$(replace_section "$existing_body" 'default' "$new_section")"

# Extract section keys in order from the result
keys_in_order="$(echo "$result" | grep -o '<!-- lcov-section:[^ ]*' | sed 's/<!-- lcov-section://')"
expected="$(printf 'default\nalpha\nzebra')"

if [[ "$keys_in_order" == "$expected" ]]; then
  pass "sections are sorted: default first, then alphabetical"
else
  fail "sections not sorted correctly. Got: $(echo "$keys_in_order" | tr '\n' ','). Expected: default,alpha,zebra"
fi

# ---------------------------------------------------------------------------
# Test 52: Old-format labeled comments are cleaned up
# ---------------------------------------------------------------------------
run_test "Section consolidation: old-format labeled comments are deleted"

event_payload="$(mktemp "${TMPDIR:-/tmp}/event-payload-XXXXXX.json")"
echo '{"pull_request": {"number": 42}}' > "$event_payload"

mock_bin="$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXXXX")"
curl_log="${mock_bin}/curl.log"

# Return both old-format labeled comment and no consolidated comment
cat > "${mock_bin}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
echo "$@" >> "$(dirname "$0")/curl.log"
if echo "$@" | grep -q "\-X DELETE" && echo "$@" | grep -q "\-w"; then
  # DELETE with status check — return HTTP 204
  echo -n '204'
elif echo "$@" | grep -q "\-X DELETE\|\-X POST\|\-X PATCH"; then
  echo '{}'
else
  echo '[{"id": 500, "body": "<!-- lcov-coverage-check:go -->\nold labeled report"}, {"id": 501, "body": "<!-- lcov-coverage-check:frontend -->\nold frontend report"}]'
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

# Should POST a new consolidated comment (no existing consolidated comment)
if grep -q '\-X POST' "$curl_log" 2>/dev/null; then
  pass "curl used POST to create new consolidated comment"
else
  fail "curl should have used POST (no existing consolidated comment)"
fi

# Should DELETE old-format labeled comments
if grep -q '\-X DELETE.*comments/500' "$curl_log" 2>/dev/null; then
  pass "old-format comment 500 was deleted"
else
  fail "old-format comment 500 should have been deleted"
fi

if grep -q '\-X DELETE.*comments/501' "$curl_log" 2>/dev/null; then
  pass "old-format comment 501 was deleted"
else
  fail "old-format comment 501 should have been deleted"
fi

if echo "$output" | grep -q "Cleaned up old-format comment"; then
  pass "output confirms old-format comment cleanup"
else
  fail "output missing old-format comment cleanup message"
fi

rm -f "$event_payload"
rm -rf "$mock_bin"

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

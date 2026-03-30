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

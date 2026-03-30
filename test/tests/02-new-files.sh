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
  INPUT_PATH="lib/" \
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
  INPUT_PATH="lib/" \
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
  INPUT_PATH="lib/" \
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

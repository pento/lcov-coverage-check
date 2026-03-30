# ---------------------------------------------------------------------------
# Test 8: Changed file coverage increased — exits 0
# ---------------------------------------------------------------------------
run_test "Changed file coverage increased: exits 0"

# widget_a.dart: baseline 75%, current 100% (increased)
# widget_b.dart: baseline 50%, current 75% (increased)
tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a lib/src/widget_b.dart:b" \
  "" \
  "lib/src/widget_a.dart:a-modified lib/src/widget_b.dart:b-modified"
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "Changed File Ratchet Check"; then
  pass "output contains 'Changed File Ratchet Check'"
else
  fail "output missing 'Changed File Ratchet Check'"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 9: Changed file coverage decreased — exits 1
# ---------------------------------------------------------------------------
run_test "Changed file coverage decreased: exits 1"

# Use decreased.lcov.info as current — widget_a goes from 75% to 25%
tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a lib/src/widget_b.dart:b" \
  "" \
  "lib/src/widget_a.dart:a-modified"
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/decreased.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 1 ]]; then
  pass "exit code is 1"
else
  fail "expected exit code 1, got $exit_code"
fi

if echo "$output" | grep -q "coverage decreased"; then
  pass "output reports coverage decrease"
else
  fail "output missing coverage decrease message"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 10: Changed file not in baseline (new to coverage) — skip, exits 0
# ---------------------------------------------------------------------------
run_test "Changed file not in baseline (new to coverage): skip, exits 0"

# Create a scenario where a modified file has no baseline LCOV entry
# We'll use current.lcov.info which has widget_a and widget_b,
# but use an empty baseline so neither file has baseline coverage data.
# Modify widget_a so it shows as modified in git diff.

tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a" \
  "" \
  "lib/src/widget_a.dart:a-modified"
)"

empty_baseline="$(mktemp "${TMPDIR:-/tmp}/empty-baseline-XXXXXX")"
: > "$empty_baseline"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$empty_baseline" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
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

if echo "$output" | grep -q "SKIP.*not in baseline"; then
  pass "output shows file skipped (not in baseline)"
else
  fail "output missing skip message for file not in baseline"
fi

cleanup_git_repo "$tmpdir"

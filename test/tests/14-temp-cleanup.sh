# ---------------------------------------------------------------------------
# Test 60: Temp files cleaned up after successful run with ignore patterns
# ---------------------------------------------------------------------------
run_test "Temp cleanup: filtered LCOV temp files removed on success"

# Use an isolated TMPDIR so we can verify cleanup
test_tmpdir="$(mktemp -d)"

output="$(
  TMPDIR="$test_tmpdir" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/with-generated.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="$(printf '%s\n%s' '*.g.dart' '*.freezed.dart')" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

leftover="$(find "$test_tmpdir" -name 'lcov-filtered-*' 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$leftover" -eq 0 ]]; then
  pass "no lcov-filtered-* temp files remain in TMPDIR"
else
  fail "expected 0 leftover temp files, found $leftover in $test_tmpdir"
fi

rm -rf "$test_tmpdir"

# ---------------------------------------------------------------------------
# Test 61: Temp files cleaned up after failed run (coverage decrease)
# ---------------------------------------------------------------------------
run_test "Temp cleanup: filtered LCOV temp files removed on failure"

# Use an isolated TMPDIR so we can verify cleanup
test_tmpdir="$(mktemp -d)"

# decreased.lcov.info (50%) vs baseline.lcov.info (62.5%) — overall ratchet fails.
# Ignore patterns are set so filter_lcov_file creates temp files for both.
output="$(
  TMPDIR="$test_tmpdir" \
  INPUT_LCOV_FILE="$FIXTURES_DIR/decreased.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="*.nonexistent" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -ne 0 ]]; then
  pass "exit code is non-zero (coverage decrease detected)"
else
  fail "expected non-zero exit code for coverage decrease, got 0"
fi

leftover="$(find "$test_tmpdir" -name 'lcov-filtered-*' 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$leftover" -eq 0 ]]; then
  pass "no lcov-filtered-* temp files remain in TMPDIR after failure"
else
  fail "expected 0 leftover temp files after failure, found $leftover in $test_tmpdir"
fi

rm -rf "$test_tmpdir"

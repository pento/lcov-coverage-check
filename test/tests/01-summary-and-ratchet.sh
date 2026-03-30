# ---------------------------------------------------------------------------
# Test 1: Summary-only mode
# ---------------------------------------------------------------------------
run_test "Summary-only mode: reports correctly, exits 0"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
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

if echo "$output" | grep -q "Summary-only mode"; then
  pass "output contains 'Summary-only mode'"
else
  fail "output missing 'Summary-only mode'"
fi

if echo "$output" | grep -q "87.50%"; then
  pass "output contains correct overall coverage (87.50%)"
else
  fail "output missing '87.50%' coverage"
fi

if echo "$output" | grep -q "Result: PASS"; then
  pass "output contains 'Result: PASS'"
else
  fail "output missing 'Result: PASS'"
fi

# ---------------------------------------------------------------------------
# Test 2: Overall coverage increased
# ---------------------------------------------------------------------------
run_test "Overall coverage increased: exits 0"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
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

if echo "$output" | grep -q "Coverage did not decrease"; then
  pass "output confirms coverage did not decrease"
else
  fail "output missing coverage increase confirmation"
fi

# ---------------------------------------------------------------------------
# Test 3: Overall coverage decreased
# ---------------------------------------------------------------------------
run_test "Overall coverage decreased: exits 1 with clear message"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/decreased.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
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

if echo "$output" | grep -q "Overall coverage decreased"; then
  pass "output contains 'Overall coverage decreased'"
else
  fail "output missing 'Overall coverage decreased'"
fi

if echo "$output" | grep -q "Result: FAIL"; then
  pass "output contains 'Result: FAIL'"
else
  fail "output missing 'Result: FAIL'"
fi

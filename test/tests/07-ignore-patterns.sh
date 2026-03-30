# ---------------------------------------------------------------------------
# Test 27: Ignore patterns — excluded files affect overall coverage
# ---------------------------------------------------------------------------
run_test "Ignore patterns: excluded files removed from overall coverage"

# with-generated.lcov.info has 4 files:
#   widget_a.dart: 4/4 (100%), widget_b.dart: 3/4 (75%),
#   widget_a.g.dart: 0/4 (0%), models/data.freezed.dart: 0/6 (0%)
# Total without filtering: 7/18 = 38.89%
# After ignoring *.g.dart and *.freezed.dart: 7/8 = 87.50%

output="$(
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

if echo "$output" | grep -q "87.50%"; then
  pass "overall coverage is 87.50% (generated files excluded)"
else
  fail "expected 87.50% coverage after ignoring generated files, got: $(echo "$output" | grep 'Overall:')"
fi

if echo "$output" | grep -q "widget_a.g.dart"; then
  fail "output should not mention widget_a.g.dart (it was ignored)"
else
  pass "ignored file widget_a.g.dart not in output"
fi

if echo "$output" | grep -q "data.freezed.dart"; then
  fail "output should not mention data.freezed.dart (it was ignored)"
else
  pass "ignored file data.freezed.dart not in output"
fi

# ---------------------------------------------------------------------------
# Test 28: Ignore patterns — new file matching ignore pattern is skipped
# ---------------------------------------------------------------------------
run_test "Ignore patterns: new file matching pattern is skipped"

tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a" \
  "lib/src/widget_b.dart:new lib/src/widget_a.g.dart:generated" \
  ""
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/with-generated.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_IGNORE_PATTERNS="*.g.dart" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if echo "$output" | grep -q "SKIP.*widget_a.g.dart.*ignore pattern"; then
  pass "generated new file skipped due to ignore pattern"
else
  fail "expected widget_a.g.dart to be skipped via ignore pattern"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 29: Ignore patterns — changed file matching ignore pattern is skipped
# ---------------------------------------------------------------------------
run_test "Ignore patterns: changed file matching pattern is skipped"

tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a lib/src/widget_a.g.dart:generated" \
  "" \
  "lib/src/widget_a.dart:a-modified lib/src/widget_a.g.dart:generated-modified"
)"

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$FIXTURES_DIR/with-generated.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="*.g.dart" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if echo "$output" | grep -q "SKIP.*widget_a.g.dart.*ignore pattern"; then
  pass "generated changed file skipped due to ignore pattern"
else
  fail "expected widget_a.g.dart to be skipped via ignore pattern"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 30: Ignore patterns — directory glob pattern
# ---------------------------------------------------------------------------
run_test "Ignore patterns: directory glob pattern excludes files"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/with-generated.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="lib/src/models/*" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if echo "$output" | grep -q "data.freezed.dart"; then
  fail "output should not mention files under lib/src/models/"
else
  pass "files under lib/src/models/ excluded by directory pattern"
fi

# Without the models dir, we have widget_a (4/4), widget_b (3/4), widget_a.g (0/4) = 7/12 = 58.33%
if echo "$output" | grep -q "58.33%"; then
  pass "overall coverage is 58.33% (models dir excluded)"
else
  fail "expected 58.33% coverage after excluding models dir, got: $(echo "$output" | grep 'Overall:')"
fi

# ---------------------------------------------------------------------------
# Test 31: Ignore patterns — empty patterns has no effect
# ---------------------------------------------------------------------------
run_test "Ignore patterns: empty patterns has no effect"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "87.50%"; then
  pass "coverage unchanged at 87.50% with empty patterns"
else
  fail "expected 87.50% coverage with empty patterns"
fi

if echo "$output" | grep -q "Ignore Patterns"; then
  fail "should not print ignore patterns header when empty"
else
  pass "no ignore patterns header when empty"
fi

# ---------------------------------------------------------------------------
# Test 32: Ignore patterns — multiple patterns with baseline comparison
# ---------------------------------------------------------------------------
run_test "Ignore patterns: multiple patterns with baseline comparison"

# Create baseline and current fixtures where generated files drag down coverage
# Baseline (with-generated): 7/18 unfiltered, but after filtering *.g.dart + *.freezed.dart: 7/8
# Current (with-generated): same fixture — coverage should match baseline
output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/with-generated.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/with-generated.lcov.info" \
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

if echo "$output" | grep -q "Coverage did not decrease"; then
  pass "filtered comparison passes correctly"
else
  fail "expected comparison pass after filtering"
fi

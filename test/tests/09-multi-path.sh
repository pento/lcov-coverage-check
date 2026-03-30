# ---------------------------------------------------------------------------
# Test 35: Multi-path — new files detected across both path prefixes
# ---------------------------------------------------------------------------
run_test "Multi-path: new files detected across both path prefixes"

tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a src/app.dart:a" \
  "lib/src/new_widget.dart:new src/new_app.dart:new" \
  ""
)"

mp_lcov="$(mktemp "${TMPDIR:-/tmp}/mp-lcov-XXXXXX")"
cat > "$mp_lcov" <<'LCOV'
TN:
SF:lib/src/widget_a.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:lib/src/new_widget.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:src/app.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:src/new_app.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

mp_base="$(mktemp "${TMPDIR:-/tmp}/mp-base-XXXXXX")"
cat > "$mp_base" <<'LCOV'
TN:
SF:lib/src/widget_a.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:src/app.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$mp_lcov" \
  INPUT_LCOV_BASE="$mp_base" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="40" \
  INPUT_PATH="$(printf '%s\n%s' 'lib/' 'src/')" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "lib/src/new_widget.dart"; then
  pass "new file under lib/ detected"
else
  fail "new file under lib/ not detected"
fi

if echo "$output" | grep -q "src/new_app.dart"; then
  pass "new file under src/ detected"
else
  fail "new file under src/ not detected"
fi

rm -f "$mp_lcov" "$mp_base"
cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 36: Multi-path — changed file ratchet works across both paths
# ---------------------------------------------------------------------------
run_test "Multi-path: changed file ratchet works across both path prefixes"

tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a src/app.dart:a" \
  "" \
  "lib/src/widget_a.dart:modified src/app.dart:modified"
)"

mp_base="$(mktemp "${TMPDIR:-/tmp}/mp-base-XXXXXX")"
cat > "$mp_base" <<'LCOV'
TN:
SF:lib/src/widget_a.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:src/app.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

mp_cur="$(mktemp "${TMPDIR:-/tmp}/mp-cur-XXXXXX")"
cat > "$mp_cur" <<'LCOV'
TN:
SF:lib/src/widget_a.dart
DA:1,1
DA:2,0
DA:3,1
DA:4,0
LF:4
LH:2
end_of_record
TN:
SF:src/app.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$mp_cur" \
  INPUT_LCOV_BASE="$mp_base" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="$(printf '%s\n%s' 'lib/' 'src/')" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 1 ]]; then
  pass "exit code is 1 (failure due to coverage decrease)"
else
  fail "expected exit code 1, got $exit_code"
fi

if echo "$output" | grep -q "widget_a.dart.*decreased"; then
  pass "coverage decrease detected for file under lib/"
else
  fail "expected coverage decrease for lib/src/widget_a.dart"
fi

rm -f "$mp_base" "$mp_cur"
cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 37: Single path with trailing newline works (backward compat)
# ---------------------------------------------------------------------------
run_test "Single path with trailing newline works correctly"

tmpdir="$(setup_git_repo \
  "lib/src/widget_a.dart:a" \
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
  INPUT_PATH="$(printf 'lib/\n')" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "new_widget.dart"; then
  pass "new file detected with trailing newline in path"
else
  fail "new file not detected"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 38: Empty path matches all files
# ---------------------------------------------------------------------------
run_test "Empty path matches all files"

tmpdir="$(setup_git_repo \
  "anywhere/file.dart:a" \
  "somewhere/new_file.dart:new" \
  ""
)"

ep_lcov="$(mktemp "${TMPDIR:-/tmp}/ep-lcov-XXXXXX")"
cat > "$ep_lcov" <<'LCOV'
TN:
SF:anywhere/file.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:somewhere/new_file.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

ep_base="$(mktemp "${TMPDIR:-/tmp}/ep-base-XXXXXX")"
cat > "$ep_base" <<'LCOV'
TN:
SF:anywhere/file.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$ep_lcov" \
  INPUT_LCOV_BASE="$ep_base" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="40" \
  INPUT_PATH="" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "somewhere/new_file.dart"; then
  pass "file outside any prefix detected with empty path"
else
  fail "expected new file to be detected with empty path"
fi

rm -f "$ep_lcov" "$ep_base"
cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 39: Empty path with no LCOV extensions matches all files
# ---------------------------------------------------------------------------
run_test "Empty path with no LCOV extensions matches all files"

tmpdir="$(setup_git_repo \
  "anywhere/file:a" \
  "somewhere/newfile:new" \
  ""
)"

# LCOV with extensionless source files — extract_lcov_extensions returns nothing
ep2_lcov="$(mktemp "${TMPDIR:-/tmp}/ep2-lcov-XXXXXX")"
cat > "$ep2_lcov" <<'LCOV'
TN:
SF:anywhere/file
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
TN:
SF:somewhere/newfile
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

ep2_base="$(mktemp "${TMPDIR:-/tmp}/ep2-base-XXXXXX")"
cat > "$ep2_base" <<'LCOV'
TN:
SF:anywhere/file
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$ep2_lcov" \
  INPUT_LCOV_BASE="$ep2_base" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="40" \
  INPUT_PATH="" \
  INPUT_CHANGED_FILE_NO_DECREASE="false" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "somewhere/newfile"; then
  pass "extensionless file detected with empty path"
else
  fail "expected new file to be detected with empty path and no extensions"
fi

rm -f "$ep2_lcov" "$ep2_base"
cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 40: Path prefixes are displayed in output
# ---------------------------------------------------------------------------
run_test "Path prefixes are displayed in output"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="$(printf '%s\n%s' 'lib/' 'src/')" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_IGNORE_PATTERNS="" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if echo "$output" | grep -q "Path Prefixes"; then
  pass "output contains 'Path Prefixes' header"
else
  fail "output missing 'Path Prefixes' header"
fi

if echo "$output" | grep -q "lib/"; then
  pass "output shows lib/ prefix"
else
  fail "output missing lib/ prefix"
fi

if echo "$output" | grep -q "src/"; then
  pass "output shows src/ prefix"
else
  fail "output missing src/ prefix"
fi

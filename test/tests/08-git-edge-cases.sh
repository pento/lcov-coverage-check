# ---------------------------------------------------------------------------
# Test 33: Shallow clone — fetches refs and detects new/modified files
# ---------------------------------------------------------------------------
run_test "Shallow clone: fetches refs and detects new/modified files"

# Create a bare repo, push base+head commits, then shallow-clone
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-shallow-XXXXXX")"
bare_repo="${tmpdir}/bare.git"
work_repo="${tmpdir}/work"
shallow_repo="${tmpdir}/shallow"

# Build the repo with commits
(
  git init -q --bare "$bare_repo"
  git clone -q "$bare_repo" "$work_repo"
  cd "$work_repo"
  git config user.email "test@test.com"
  git config user.name "Test"

  # Base commit with one existing file
  mkdir -p lib/src
  echo "base content" > lib/src/widget_a.dart
  git add lib/src/widget_a.dart
  git commit -q -m "base commit"
  git tag base_ref
  git push -q origin main 2>/dev/null || git push -q origin master 2>/dev/null || true
  git push -q origin base_ref

  # Head commit: add a new file, modify the existing one
  echo "new file" > lib/src/new_widget.dart
  echo "modified content" > lib/src/widget_a.dart
  git add lib/src/new_widget.dart lib/src/widget_a.dart
  git commit -q -m "head commit"
  git tag head_ref
  git push -q origin head_ref
) 2>/dev/null

# Shallow clone with depth=1 of head_ref only (simulates actions/checkout default)
git clone -q --depth=1 --branch head_ref "$bare_repo" "$shallow_repo" 2>/dev/null

# Create LCOV data that covers the new and existing file
lcov_current="$(mktemp "${TMPDIR:-/tmp}/lcov-shallow-current-XXXXXX")"
cat > "$lcov_current" <<'LCOV'
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
LF:2
LH:2
end_of_record
LCOV

lcov_baseline="$(mktemp "${TMPDIR:-/tmp}/lcov-shallow-baseline-XXXXXX")"
cat > "$lcov_baseline" <<'LCOV'
TN:
SF:lib/src/widget_a.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
LF:4
LH:4
end_of_record
LCOV

output="$(
  cd "$shallow_repo" && \
  INPUT_LCOV_FILE="$lcov_current" \
  INPUT_LCOV_BASE="$lcov_baseline" \
  INPUT_BASE_REF="base_ref" \
  INPUT_HEAD_REF="head_ref" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="50" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
  echo "  Output: $output"
fi

if echo "$output" | grep -q "new_widget.dart"; then
  pass "new file detected in shallow clone"
else
  fail "new file not detected in shallow clone"
  echo "  Output: $output"
fi

if ! echo "$output" | grep -q "No new files detected"; then
  pass "does not say 'No new files detected'"
else
  fail "incorrectly says 'No new files detected'"
fi

if ! echo "$output" | grep -q "::warning::"; then
  pass "no warning emitted (refs fetched successfully)"
else
  fail "unexpected warning emitted"
fi

rm -f "$lcov_current" "$lcov_baseline"
rm -rf "$tmpdir"

# ---------------------------------------------------------------------------
# Test 34: Warning emitted when git diff fails (unreachable refs)
# ---------------------------------------------------------------------------
run_test "Warning emitted when git diff fails with unreachable refs"

# Create a simple repo with no remote — fetch will fail, refs don't exist
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-warn-XXXXXX")"
(
  cd "$tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p lib/src
  echo "content" > lib/src/widget.dart
  git add lib/src/widget.dart
  git commit -q -m "initial"
)

lcov_file="$(mktemp "${TMPDIR:-/tmp}/lcov-warn-XXXXXX")"
cat > "$lcov_file" <<'LCOV'
TN:
SF:lib/src/widget.dart
DA:1,1
LF:1
LH:1
end_of_record
LCOV

lcov_base="$(mktemp "${TMPDIR:-/tmp}/lcov-warn-base-XXXXXX")"
cat > "$lcov_base" <<'LCOV'
TN:
SF:lib/src/widget.dart
DA:1,1
LF:1
LH:1
end_of_record
LCOV

output="$(
  cd "$tmpdir" && \
  INPUT_LCOV_FILE="$lcov_file" \
  INPUT_LCOV_BASE="$lcov_base" \
  INPUT_BASE_REF="nonexistent-sha-abc123" \
  INPUT_HEAD_REF="nonexistent-sha-def456" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0 (action does not crash)"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "::warning::Failed to detect new files"; then
  pass "warning emitted for failed new file detection"
else
  fail "expected warning about failed new file detection"
  echo "  Output: $output"
fi

if echo "$output" | grep -q "::warning::Failed to detect modified files"; then
  pass "warning emitted for failed modified file detection"
else
  fail "expected warning about failed modified file detection"
  echo "  Output: $output"
fi

rm -f "$lcov_file" "$lcov_base"
rm -rf "$tmpdir"

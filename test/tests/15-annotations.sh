# ---------------------------------------------------------------------------
# Test 62: Annotation helpers — emit_annotation and build_annotation_title
# produce exact workflow-command output
# ---------------------------------------------------------------------------
run_test "Annotation helpers: emit_annotation and build_annotation_title exact output"

source "$SCRIPT_DIR/../scripts/lib/common.sh"

result="$(emit_annotation warning "T:1,2" "100% done"$'\n'"next" "dir/a,b:c.dart")"
expected='::warning file=dir/a%2Cb%3Ac.dart,line=1,title=T%3A1%2C2::100%25 done%0Anext'
if [[ "$result" == "$expected" ]]; then
  pass "emit_annotation escapes file, title and message data correctly"
else
  fail "emit_annotation output mismatch. Got: $result"
fi

result="$(emit_annotation error "Coverage" "x")"
if [[ "$result" == "::error title=Coverage::x" ]]; then
  pass "emit_annotation without a file omits the file/line properties"
else
  fail "emit_annotation output mismatch. Got: $result"
fi

result="$(build_annotation_title "")"
if [[ "$result" == "Coverage" ]]; then
  pass "build_annotation_title with no label returns 'Coverage'"
else
  fail "build_annotation_title mismatch. Got: $result"
fi

result="$(build_annotation_title go)"
if [[ "$result" == "Coverage (go)" ]]; then
  pass "build_annotation_title with a label returns 'Coverage (LABEL)'"
else
  fail "build_annotation_title mismatch. Got: $result"
fi

# ---------------------------------------------------------------------------
# Test 63: Per-file coverage lines use the new em-dash format, are wrapped in
# a titled log group, and never match a problem-matcher shape
# ---------------------------------------------------------------------------
run_test "Per-file coverage: new format, grouped, and matcher-safe"

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

if echo "$output" | grep -qF "lib/src/widget_a.dart — 100.00% (4/4)"; then
  pass "widget_a per-file line uses the em-dash format"
else
  fail "expected 'lib/src/widget_a.dart — 100.00% (4/4)' in output"
fi

if echo "$output" | grep -qF "lib/src/widget_b.dart — 75.00% (3/4)"; then
  pass "widget_b per-file line uses the em-dash format"
else
  fail "expected 'lib/src/widget_b.dart — 75.00% (3/4)' in output"
fi

if echo "$output" | grep -qF "::group::Per-File Coverage (2 files)"; then
  pass "per-file listing opens a titled log group"
else
  fail "expected '::group::Per-File Coverage (2 files)' in output"
fi

if echo "$output" | grep -qF "::endgroup::"; then
  pass "per-file listing closes the log group"
else
  fail "expected '::endgroup::' in output"
fi

grouped_lines="$(awk '/^::group::Per-File Coverage/{f=1;next} /^::endgroup::/{f=0} f' <<< "$output")"
if echo "$grouped_lines" | grep -qF "lib/src/widget_a.dart — 100.00% (4/4)" \
  && echo "$grouped_lines" | grep -qF "lib/src/widget_b.dart — 75.00% (3/4)"; then
  pass "both per-file lines fall between ::group:: and ::endgroup::"
else
  fail "expected both per-file lines inside the group"
fi

if echo "$output" | grep -qF "== Per-File Coverage =="; then
  fail "old '== Per-File Coverage ==' header should no longer appear"
else
  pass "old '== Per-File Coverage ==' header no longer appears"
fi

# actions/setup-go registers a problem matcher with this shape:
#   ^\s*(.+\.go):(?:(\d+):(\d+):)? (.*)
# (line:column optional), which turns any "<path>.go: <message>" line into an
# error annotation. Generalised here to any extension to guard the em-dash
# format against the same failure mode for other languages' matchers.
if echo "$output" | grep -Eq '^[[:space:]]*.+\.[A-Za-z0-9]+:([0-9]+:[0-9]+:)? '; then
  fail "a console line matches the setup-go problem-matcher shape"
else
  pass "no console line matches the setup-go problem-matcher shape"
fi

# ---------------------------------------------------------------------------
# Test 64: No matcher-shaped lines in a full comparison run (FAIL, PASS,
# SKIP and ::error lines all present)
# ---------------------------------------------------------------------------
run_test "Full comparison run: no console line matches the setup-go problem-matcher shape"

# widget_a.dart: baseline 75%, decreased 25% (changed-file FAIL)
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

cleanup_git_repo "$tmpdir"

# See Test 63 for the setup-go matcher shape this guards against.
if echo "$output" | grep -Eq '^[[:space:]]*.+\.[A-Za-z0-9]+:([0-9]+:[0-9]+:)? '; then
  fail "a console line matches the setup-go problem-matcher shape (changed-file FAIL run)"
else
  pass "no console line matches the setup-go problem-matcher shape (changed-file FAIL run)"
fi

# Confirm this run actually exercises a bare-path FAIL line — otherwise the
# matcher-shape check above would trivially pass on an empty case.
if echo "$output" | grep -qE '^  FAIL: lib/src/widget_a\.dart$'; then
  pass "this run does exercise a bare-path FAIL line (matcher-safety check is non-vacuous)"
else
  fail "expected bare path line '  FAIL: lib/src/widget_a.dart' not found"
  echo "  Output: $output"
fi

# widget_a.g.dart is modified but matches the ignore pattern (SKIP)
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

cleanup_git_repo "$tmpdir"

# See Test 63 for the setup-go matcher shape this guards against.
if echo "$output" | grep -Eq '^[[:space:]]*.+\.[A-Za-z0-9]+:([0-9]+:[0-9]+:)? '; then
  fail "a console line matches the setup-go problem-matcher shape (ignore-pattern SKIP run)"
else
  pass "no console line matches the setup-go problem-matcher shape (ignore-pattern SKIP run)"
fi

# ---------------------------------------------------------------------------
# Test 65: Overall ratchet FAIL emits an error annotation
# ---------------------------------------------------------------------------
run_test "Overall ratchet FAIL: emits a titled error annotation"

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

if echo "$output" | grep -qF "::error title=Coverage::Overall coverage decreased: 50.00%25 < 62.50%25"; then
  pass "overall ratchet FAIL emits the expected error annotation"
else
  fail "expected overall ratchet error annotation not found"
  echo "  Output: $output"
fi

# The overall ratchet has no associated file, so its console echo was removed
# entirely (not replaced with a bare path) — only the annotation carries it.
if echo "$output" | grep -qF "FAIL:"; then
  fail "overall ratchet failure should not print any console 'FAIL:' line"
else
  pass "overall ratchet failure prints no console 'FAIL:' line (annotation only)"
fi

# ---------------------------------------------------------------------------
# Test 66: New file below minimum emits a file-scoped error annotation
# ---------------------------------------------------------------------------
run_test "New file below minimum: emits a file-scoped error annotation"

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

if echo "$output" | grep -qF "::error file=lib/src/new_widget.dart,line=1,title=Coverage::New file coverage 50.00%25 is below the 80%25 minimum"; then
  pass "new-file-below-minimum FAIL emits the expected file-scoped error annotation"
else
  fail "expected new-file-below-minimum error annotation not found"
  echo "  Output: $output"
fi

# Console line is "  FAIL: <path>" — mirrors the PASS lines' format, with the
# path at end-of-line and no trailing colon (which would make it match a
# setup-go-style problem matcher).
if echo "$output" | grep -qE '^  FAIL: lib/src/new_widget\.dart$'; then
  pass "new-file-below-minimum prints '  FAIL: <path>' with the path at end-of-line"
else
  fail "expected bare path line '  FAIL: lib/src/new_widget.dart' not found"
  echo "  Output: $output"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 67: New file not in LCOV emits a file-scoped error annotation
# ---------------------------------------------------------------------------
run_test "New file not in LCOV: emits a file-scoped error annotation"

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

if echo "$output" | grep -qF "::error file=lib/src/unknown_widget.dart,line=1,title=Coverage::New file has no coverage data (0.00%25 < 80%25 minimum)"; then
  pass "new-file-not-in-LCOV FAIL emits the expected file-scoped error annotation"
else
  fail "expected new-file-not-in-LCOV error annotation not found"
  echo "  Output: $output"
fi

# Console line is "  FAIL: <path>" — mirrors the PASS lines' format, with the
# path at end-of-line and no trailing colon (which would make it match a
# setup-go-style problem matcher).
if echo "$output" | grep -qE '^  FAIL: lib/src/unknown_widget\.dart$'; then
  pass "new-file-not-in-LCOV prints '  FAIL: <path>' with the path at end-of-line"
else
  fail "expected bare path line '  FAIL: lib/src/unknown_widget.dart' not found"
  echo "  Output: $output"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 68: Changed-file decrease emits a file-scoped error annotation
# (alongside the overall-ratchet annotation, since the same run fails both)
# ---------------------------------------------------------------------------
run_test "Changed file decreased: emits a file-scoped error annotation"

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

if echo "$output" | grep -qF "::error file=lib/src/widget_a.dart,line=1,title=Coverage::Coverage decreased from 75.00%25 to 25.00%25"; then
  pass "changed-file FAIL emits the expected file-scoped error annotation"
else
  fail "expected changed-file error annotation not found"
  echo "  Output: $output"
fi

if echo "$output" | grep -qF "::error title=Coverage::Overall coverage decreased: 50.00%25 < 62.50%25"; then
  pass "the same run also emits the overall-ratchet error annotation"
else
  fail "expected overall-ratchet error annotation not found in the same run"
  echo "  Output: $output"
fi

# Console line is "  FAIL: <path>" — mirrors the PASS lines' format, with the
# path at end-of-line and no trailing colon (which would make it match a
# setup-go-style problem matcher).
if echo "$output" | grep -qE '^  FAIL: lib/src/widget_a\.dart$'; then
  pass "changed-file FAIL prints '  FAIL: <path>' with the path at end-of-line"
else
  fail "expected bare path line '  FAIL: lib/src/widget_a.dart' not found"
  echo "  Output: $output"
fi

# This run fails BOTH the overall ratchet (no associated file) and the
# changed-file check (has an associated file). The overall ratchet still
# prints nothing before its annotation, so exactly ONE "  FAIL: " console
# line should appear in this run — the changed-file one.
fail_line_count="$(grep -c '^  FAIL: ' <<< "$output" || true)"
if [[ "$fail_line_count" -eq 1 ]]; then
  pass "exactly one '  FAIL: ' console line appears (the overall ratchet contributes none)"
else
  fail "expected exactly one '  FAIL: ' console line, got ${fail_line_count}"
  echo "  Output: $output"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 69: coverage-label appears in the annotation title
# ---------------------------------------------------------------------------
run_test "Coverage label: appears in the annotation title"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/decreased.lcov.info" \
  INPUT_LCOV_BASE="$FIXTURES_DIR/baseline.lcov.info" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  INPUT_COVERAGE_LABEL="go" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if echo "$output" | grep -qF "::error title=Coverage (go)::Overall coverage decreased: 50.00%25 < 62.50%25"; then
  pass "annotation title includes the coverage label"
else
  fail "expected annotation titled 'Coverage (go)'"
  echo "  Output: $output"
fi

# ---------------------------------------------------------------------------
# Test 70: Passing run emits no error annotations
# ---------------------------------------------------------------------------
run_test "Passing run: emits no error annotations"

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

if echo "$output" | grep -q '^::error'; then
  fail "unexpected error annotation on a passing run"
else
  pass "no error annotation emitted on a passing run"
fi

cleanup_git_repo "$tmpdir"

# ---------------------------------------------------------------------------
# Test 71: Discarded coverage-label warning is titled
# ---------------------------------------------------------------------------
run_test "Discarded coverage-label: warning is titled 'Coverage'"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="80" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  INPUT_COVERAGE_LABEL="!!!" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  pass "exit code is 0"
else
  fail "expected exit code 0, got $exit_code"
fi

if echo "$output" | grep -q "Result: PASS"; then
  pass "output contains 'Result: PASS'"
else
  fail "output missing 'Result: PASS'"
fi

if echo "$output" | grep -qF "::warning title=Coverage::coverage-label contained only invalid characters and was discarded"; then
  pass "discarded-label warning carries the 'Coverage' title"
else
  fail "expected titled discarded-label warning not found"
  echo "  Output: $output"
fi

# ---------------------------------------------------------------------------
# Test 72: Invalid new-file-minimum-coverage error carries the label
# (proves the validation block now runs after the title is computed)
# ---------------------------------------------------------------------------
run_test "Invalid new-file-minimum-coverage: error annotation carries the label"

output="$(
  INPUT_LCOV_FILE="$FIXTURES_DIR/current.lcov.info" \
  INPUT_LCOV_BASE="" \
  INPUT_BASE_REF="" \
  INPUT_HEAD_REF="HEAD" \
  INPUT_NEW_FILE_MINIMUM_COVERAGE="abc" \
  INPUT_PATH="lib/" \
  INPUT_CHANGED_FILE_NO_DECREASE="true" \
  INPUT_GITHUB_TOKEN="" \
  INPUT_COVERAGE_LABEL="go" \
  bash "$CHECK_SCRIPT" 2>&1
)" && exit_code=0 || exit_code=$?

if [[ $exit_code -ne 0 ]]; then
  pass "exit code is non-zero for invalid threshold"
else
  fail "expected non-zero exit code for invalid threshold, got 0"
fi

if echo "$output" | grep -qF "::error title=Coverage (go)::new-file-minimum-coverage must be a number between 0 and 100 (got: 'abc')"; then
  pass "invalid-threshold error annotation carries the 'Coverage (go)' title"
else
  fail "expected labelled invalid-threshold error annotation not found"
  echo "  Output: $output"
fi

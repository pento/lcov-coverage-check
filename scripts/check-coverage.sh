#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# check-coverage.sh
#
# Reads LCOV coverage files, computes overall and per-file coverage, and
# optionally compares against a baseline.
#
# Environment variables (inputs):
#   INPUT_LCOV_FILE                 - Path to current LCOV coverage file (required)
#   INPUT_LCOV_BASE                 - Path to baseline LCOV file (optional)
#   INPUT_BASE_REF                  - Git ref for base branch (optional)
#   INPUT_HEAD_REF                  - Git ref for PR head (default: HEAD)
#   INPUT_NEW_FILE_MINIMUM_COVERAGE - Min coverage % for new files (default: 80)
#   INPUT_NEW_FILE_PATH_PREFIX      - Only enforce under this prefix (default: lib/)
#   INPUT_CHANGED_FILE_NO_DECREASE  - Require no per-file decrease (default: true)
#   INPUT_GITHUB_TOKEN              - Token for PR comments (optional)
#
# GitHub Actions environment:
#   GITHUB_STEP_SUMMARY  - File to write markdown summary
#   GITHUB_OUTPUT         - File to write outputs
#   GITHUB_REPOSITORY     - owner/repo
#   GITHUB_EVENT_PATH     - Path to event payload JSON (set by Actions)
###############################################################################

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
INPUT_LCOV_FILE="${INPUT_LCOV_FILE:-}"
INPUT_LCOV_BASE="${INPUT_LCOV_BASE:-}"
INPUT_BASE_REF="${INPUT_BASE_REF:-}"
INPUT_HEAD_REF="${INPUT_HEAD_REF:-HEAD}"
INPUT_NEW_FILE_MINIMUM_COVERAGE="${INPUT_NEW_FILE_MINIMUM_COVERAGE:-80}"
INPUT_NEW_FILE_PATH_PREFIX="${INPUT_NEW_FILE_PATH_PREFIX:-lib/}"
INPUT_CHANGED_FILE_NO_DECREASE="${INPUT_CHANGED_FILE_NO_DECREASE:-true}"
INPUT_GITHUB_TOKEN="${INPUT_GITHUB_TOKEN:-}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# write_output KEY VALUE — append to $GITHUB_OUTPUT if available
write_output() {
  local key="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "$GITHUB_OUTPUT"
  fi
}

# append_summary TEXT — append markdown to $GITHUB_STEP_SUMMARY if available
append_summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "$1" >> "$GITHUB_STEP_SUMMARY"
  fi
}

# ---------------------------------------------------------------------------
# LCOV parsing
# ---------------------------------------------------------------------------

# parse_lcov_overall FILE
#   Prints a single line: "hit found percentage"
#   If the file is empty or missing, prints "0 0 0"
parse_lcov_overall() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    echo "0 0 0"
    return
  fi
  awk '
    BEGIN { total_hit = 0; total_found = 0 }
    /^LH:/ { total_hit += substr($0, 4) }
    /^LF:/ { total_found += substr($0, 4) }
    END {
      if (total_found > 0)
        printf "%d %d %.4f\n", total_hit, total_found, (total_hit / total_found) * 100
      else
        printf "0 0 0\n"
    }
  ' "$file"
}

# parse_lcov_per_file FILE
#   Prints lines of: "filepath hit found"
#   One line per source file record.
parse_lcov_per_file() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    return
  fi
  awk '
    /^SF:/ { sf = substr($0, 4); hit = 0; found = 0 }
    /^LH:/ { hit = substr($0, 4) }
    /^LF:/ { found = substr($0, 4) }
    /^end_of_record/ { print sf, hit, found }
  ' "$file"
}

# coverage_pct HIT FOUND — prints percentage via awk
coverage_pct() {
  awk -v h="$1" -v f="$2" 'BEGIN {
    if (f+0 > 0) printf "%.4f", (h / f) * 100; else printf "0"
  }'
}

# compare_floats A OP B — returns 0 (true) or 1 (false)
#   OP: "lt", "le", "gt", "ge", "eq"
compare_floats() {
  awk -v a="$1" -v op="$2" -v b="$3" 'BEGIN {
    if (op == "lt") exit !(a + 0 < b + 0)
    if (op == "le") exit !(a + 0 <= b + 0)
    if (op == "gt") exit !(a + 0 > b + 0)
    if (op == "ge") exit !(a + 0 >= b + 0)
    if (op == "eq") exit !(a + 0 == b + 0)
    exit 1
  }'
}

# format_pct VALUE — prints value with 2 decimal places
format_pct() {
  awk -v v="$1" 'BEGIN { printf "%.2f", v + 0 }'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

failed=false
failure_messages=()

# Parse current coverage
read -r cur_hit cur_found cur_pct <<< "$(parse_lcov_overall "$INPUT_LCOV_FILE")"
cur_pct_fmt="$(format_pct "$cur_pct")"

echo "== Current Coverage =="
echo "  Overall: ${cur_pct_fmt}% (${cur_hit}/${cur_found} lines)"

# Per-file breakdown
echo ""
echo "== Per-File Coverage =="
per_file_current=""
if [[ -s "$INPUT_LCOV_FILE" ]]; then
  per_file_current="$(parse_lcov_per_file "$INPUT_LCOV_FILE")"
  while IFS=' ' read -r pf_path pf_hit pf_found; do
    pf_pct="$(coverage_pct "$pf_hit" "$pf_found")"
    pf_pct_fmt="$(format_pct "$pf_pct")"
    echo "  ${pf_path}: ${pf_pct_fmt}% (${pf_hit}/${pf_found})"
  done <<< "$per_file_current"
fi

# ---------------------------------------------------------------------------
# Summary-only mode
# ---------------------------------------------------------------------------
if [[ -z "$INPUT_LCOV_BASE" ]]; then
  echo ""
  echo "== Summary-only mode (no baseline provided) =="

  summary_md="## Coverage Summary\n\n"
  summary_md+="**Overall coverage: ${cur_pct_fmt}%** (${cur_hit}/${cur_found} lines)\n\n"
  summary_md+="| File | Coverage | Lines |\n"
  summary_md+="|------|----------|-------|\n"
  if [[ -n "$per_file_current" ]]; then
    while IFS=' ' read -r pf_path pf_hit pf_found; do
      pf_pct="$(coverage_pct "$pf_hit" "$pf_found")"
      pf_pct_fmt="$(format_pct "$pf_pct")"
      summary_md+="| \`${pf_path}\` | ${pf_pct_fmt}% | ${pf_hit}/${pf_found} |\n"
    done <<< "$per_file_current"
  fi

  append_summary "$(echo -e "$summary_md")"

  write_output "overall-coverage" "$cur_pct_fmt"
  write_output "baseline-coverage" ""
  write_output "passed" "true"

  echo ""
  echo "Result: PASS (summary-only mode)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Comparison mode
# ---------------------------------------------------------------------------
echo ""
echo "== Comparison Mode =="

# Parse baseline
read -r base_hit base_found base_pct <<< "$(parse_lcov_overall "$INPUT_LCOV_BASE")"
base_pct_fmt="$(format_pct "$base_pct")"

echo "  Baseline: ${base_pct_fmt}% (${base_hit}/${base_found} lines)"
echo "  Current:  ${cur_pct_fmt}% (${cur_hit}/${cur_found} lines)"

per_file_baseline=""
if [[ -s "$INPUT_LCOV_BASE" ]]; then
  per_file_baseline="$(parse_lcov_per_file "$INPUT_LCOV_BASE")"
fi

# --- 1. Overall ratchet check ---
echo ""
echo "-- Overall Ratchet Check --"
if compare_floats "$cur_pct" "lt" "$base_pct"; then
  msg="Overall coverage decreased: ${cur_pct_fmt}% < ${base_pct_fmt}%"
  echo "  FAIL: $msg"
  failure_messages+=("$msg")
  failed=true
else
  echo "  PASS: Coverage did not decrease (${cur_pct_fmt}% >= ${base_pct_fmt}%)"
fi

# --- 2. New-file check ---
new_file_results=""
if [[ -n "$INPUT_BASE_REF" ]]; then
  echo ""
  echo "-- New File Coverage Check (minimum: ${INPUT_NEW_FILE_MINIMUM_COVERAGE}%) --"

  base_ref="$INPUT_BASE_REF"
  head_ref="$INPUT_HEAD_REF"
  prefix="$INPUT_NEW_FILE_PATH_PREFIX"

  # Build the git diff command for new files
  if [[ -n "$prefix" ]]; then
    new_files="$(git diff --name-only --diff-filter=A "${base_ref}...${head_ref}" -- "${prefix}*.dart" 2>/dev/null || true)"
  else
    new_files="$(git diff --name-only --diff-filter=A "${base_ref}...${head_ref}" -- '*.dart' 2>/dev/null || true)"
  fi

  if [[ -z "$new_files" ]]; then
    echo "  No new files detected."
  else
    while IFS= read -r nf; do
      [[ -z "$nf" ]] && continue

      # Look up file in current LCOV per-file data
      nf_hit=""
      nf_found=""
      if [[ -n "$per_file_current" ]]; then
        while IFS=' ' read -r pf_path pf_hit pf_found; do
          if [[ "$pf_path" == "$nf" ]]; then
            nf_hit="$pf_hit"
            nf_found="$pf_found"
            break
          fi
        done <<< "$per_file_current"
      fi

      if [[ -z "$nf_hit" ]]; then
        # Not found in LCOV at all → 0%
        nf_pct="0"
        nf_pct_fmt="0.00"
        msg="New file \`${nf}\` not found in LCOV data (0% coverage, minimum: ${INPUT_NEW_FILE_MINIMUM_COVERAGE}%)"
        echo "  FAIL: $msg"
        failure_messages+=("$msg")
        failed=true
        new_file_results+="| \`${nf}\` | ${nf_pct_fmt}% | 0/0 | FAIL |\n"
      elif [[ "$nf_found" == "0" ]]; then
        # No instrumentable lines → PASS
        echo "  PASS: ${nf} — no instrumentable lines (LF:0)"
        new_file_results+="| \`${nf}\` | N/A | 0/0 | PASS (no lines) |\n"
      else
        nf_pct="$(coverage_pct "$nf_hit" "$nf_found")"
        nf_pct_fmt="$(format_pct "$nf_pct")"
        if compare_floats "$nf_pct" "lt" "$INPUT_NEW_FILE_MINIMUM_COVERAGE"; then
          msg="New file \`${nf}\` has ${nf_pct_fmt}% coverage (minimum: ${INPUT_NEW_FILE_MINIMUM_COVERAGE}%)"
          echo "  FAIL: $msg"
          failure_messages+=("$msg")
          failed=true
          new_file_results+="| \`${nf}\` | ${nf_pct_fmt}% | ${nf_hit}/${nf_found} | FAIL |\n"
        else
          echo "  PASS: ${nf} — ${nf_pct_fmt}% >= ${INPUT_NEW_FILE_MINIMUM_COVERAGE}%"
          new_file_results+="| \`${nf}\` | ${nf_pct_fmt}% | ${nf_hit}/${nf_found} | PASS |\n"
        fi
      fi
    done <<< "$new_files"
  fi
fi

# --- 3. Changed-file ratchet check ---
changed_file_results=""
if [[ "$INPUT_CHANGED_FILE_NO_DECREASE" == "true" && -n "$INPUT_BASE_REF" ]]; then
  echo ""
  echo "-- Changed File Ratchet Check --"

  base_ref="$INPUT_BASE_REF"
  head_ref="$INPUT_HEAD_REF"
  prefix="$INPUT_NEW_FILE_PATH_PREFIX"

  if [[ -n "$prefix" ]]; then
    modified_files="$(git diff --name-only --diff-filter=M "${base_ref}...${head_ref}" -- "${prefix}*.dart" 2>/dev/null || true)"
  else
    modified_files="$(git diff --name-only --diff-filter=M "${base_ref}...${head_ref}" -- '*.dart' 2>/dev/null || true)"
  fi

  if [[ -z "$modified_files" ]]; then
    echo "  No modified files detected."
  else
    while IFS= read -r mf; do
      [[ -z "$mf" ]] && continue

      # Look up in baseline
      mf_base_hit=""
      mf_base_found=""
      if [[ -n "$per_file_baseline" ]]; then
        while IFS=' ' read -r pf_path pf_hit pf_found; do
          if [[ "$pf_path" == "$mf" ]]; then
            mf_base_hit="$pf_hit"
            mf_base_found="$pf_found"
            break
          fi
        done <<< "$per_file_baseline"
      fi

      if [[ -z "$mf_base_hit" ]]; then
        echo "  SKIP: ${mf} — not in baseline LCOV (new to coverage)"
        changed_file_results+="| \`${mf}\` | N/A | N/A | SKIP (new to coverage) |\n"
        continue
      fi

      mf_base_pct="$(coverage_pct "$mf_base_hit" "$mf_base_found")"
      mf_base_pct_fmt="$(format_pct "$mf_base_pct")"

      # Look up in current
      mf_cur_hit=""
      mf_cur_found=""
      if [[ -n "$per_file_current" ]]; then
        while IFS=' ' read -r pf_path pf_hit pf_found; do
          if [[ "$pf_path" == "$mf" ]]; then
            mf_cur_hit="$pf_hit"
            mf_cur_found="$pf_found"
            break
          fi
        done <<< "$per_file_current"
      fi

      if [[ -z "$mf_cur_hit" ]]; then
        # Not in current LCOV → 0%
        mf_cur_pct="0"
        mf_cur_pct_fmt="0.00"
      else
        mf_cur_pct="$(coverage_pct "$mf_cur_hit" "$mf_cur_found")"
        mf_cur_pct_fmt="$(format_pct "$mf_cur_pct")"
      fi

      if compare_floats "$mf_cur_pct" "lt" "$mf_base_pct"; then
        msg="Modified file \`${mf}\` coverage decreased: ${mf_cur_pct_fmt}% < ${mf_base_pct_fmt}%"
        echo "  FAIL: $msg"
        failure_messages+=("$msg")
        failed=true
        changed_file_results+="| \`${mf}\` | ${mf_base_pct_fmt}% | ${mf_cur_pct_fmt}% | FAIL |\n"
      else
        echo "  PASS: ${mf} — ${mf_cur_pct_fmt}% >= ${mf_base_pct_fmt}%"
        changed_file_results+="| \`${mf}\` | ${mf_base_pct_fmt}% | ${mf_cur_pct_fmt}% | PASS |\n"
      fi
    done <<< "$modified_files"
  fi
fi

# --- 4. Write summary ---
result_icon="$( [[ "$failed" == "true" ]] && echo "❌" || echo "✅" )"
result_text="$( [[ "$failed" == "true" ]] && echo "FAIL" || echo "PASS" )"

summary_md="## ${result_icon} Coverage Report\n\n"
summary_md+="| Metric | Value |\n"
summary_md+="|--------|-------|\n"
summary_md+="| Current coverage | **${cur_pct_fmt}%** (${cur_hit}/${cur_found}) |\n"
summary_md+="| Baseline coverage | **${base_pct_fmt}%** (${base_hit}/${base_found}) |\n"
summary_md+="| Result | **${result_text}** |\n\n"

if [[ -n "$new_file_results" ]]; then
  summary_md+="### New Files\n\n"
  summary_md+="| File | Coverage | Lines | Status |\n"
  summary_md+="|------|----------|-------|--------|\n"
  summary_md+="${new_file_results}\n"
fi

if [[ -n "$changed_file_results" ]]; then
  summary_md+="### Changed Files\n\n"
  summary_md+="| File | Baseline | Current | Status |\n"
  summary_md+="|------|----------|---------|--------|\n"
  summary_md+="${changed_file_results}\n"
fi

if [[ "$failed" == "true" ]]; then
  summary_md+="### Failures\n\n"
  for msg in "${failure_messages[@]}"; do
    summary_md+="- ${msg}\n"
  done
fi

append_summary "$(echo -e "$summary_md")"

# --- 5. Post PR comment ---
# Extract PR number from event payload (works for pull_request and issue_comment events)
pr_number=""
if [[ -n "${GITHUB_EVENT_PATH:-}" && -f "${GITHUB_EVENT_PATH:-}" ]]; then
  pr_number="$(jq -r '.pull_request.number // .number // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)"
fi

if [[ -n "$INPUT_GITHUB_TOKEN" && -n "${GITHUB_REPOSITORY:-}" && -n "$pr_number" ]]; then
  echo ""
  echo "-- Posting PR Comment --"

  comment_marker="<!-- lcov-coverage-check -->"
  comment_body="${comment_marker}\n${summary_md}"
  comment_body_json="$(echo -e "$comment_body" | jq -Rs '.')"

  # Look for existing comment
  existing_comment_id="$(
    curl -s -H "Authorization: token ${INPUT_GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${pr_number}/comments?per_page=100" \
    | jq -r ".[] | select(.body | startswith(\"${comment_marker}\")) | .id" \
    | head -1 || true
  )"

  if [[ -n "$existing_comment_id" && "$existing_comment_id" != "null" ]]; then
    # Update existing comment
    curl -s -X PATCH \
      -H "Authorization: token ${INPUT_GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/comments/${existing_comment_id}" \
      -d "{\"body\": ${comment_body_json}}" > /dev/null
    echo "  Updated existing PR comment (ID: ${existing_comment_id})"
  else
    # Create new comment
    curl -s -X POST \
      -H "Authorization: token ${INPUT_GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${pr_number}/comments" \
      -d "{\"body\": ${comment_body_json}}" > /dev/null
    echo "  Created new PR comment"
  fi
fi

# --- 6. Set outputs ---
write_output "overall-coverage" "$cur_pct_fmt"
write_output "baseline-coverage" "$base_pct_fmt"
write_output "passed" "$( [[ "$failed" == "true" ]] && echo "false" || echo "true" )"

# --- 7. Exit ---
echo ""
if [[ "$failed" == "true" ]]; then
  echo "Result: FAIL"
  for msg in "${failure_messages[@]}"; do
    echo "  - $msg"
  done
  exit 1
else
  echo "Result: PASS"
  exit 0
fi

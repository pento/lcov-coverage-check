#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# retrieve-baseline.sh
#
# Retrieves the baseline LCOV artifact from the latest successful
# default-branch run of the same workflow. Also auto-detects git refs
# from the PR event payload.
#
# Environment variables (inputs):
#   INPUT_GITHUB_TOKEN  - GitHub token for API access (required)
#   INPUT_COVERAGE_LABEL - Label to distinguish multiple coverage checks (optional)
#
# GitHub Actions environment:
#   GITHUB_OUTPUT       - File to write outputs
#   GITHUB_REPOSITORY   - owner/repo
#   GITHUB_RUN_ID       - Current workflow run ID
#   GITHUB_API_URL      - API base URL (defaults to https://api.github.com)
#   GITHUB_EVENT_PATH   - Path to event payload JSON
#
# Outputs (via $GITHUB_OUTPUT):
#   downloaded    - "true" if baseline was successfully retrieved
#   baseline-path - path to the downloaded baseline LCOV file
#   base-ref      - base SHA from PR event payload
#   head-ref      - head SHA from PR event payload
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# On any error, gracefully fall back to summary-only mode
trap 'emit_annotation notice "${annotation_title:-Coverage}" "Baseline artifact retrieval failed — running in summary-only mode"; write_output "downloaded" "false"; exit 0' ERR

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
INPUT_COVERAGE_LABEL="${INPUT_COVERAGE_LABEL:-}"
# Sanitize coverage label: lowercase, alphanumeric + hyphens only
if [[ -n "$INPUT_COVERAGE_LABEL" ]]; then
  INPUT_COVERAGE_LABEL="$(printf '%s' "$INPUT_COVERAGE_LABEL" | tr '[:upper:]' '[:lower:]' | tr '\n\r' '-' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')"
  if [[ -z "$INPUT_COVERAGE_LABEL" ]]; then
    emit_annotation warning "Coverage" "coverage-label contained only invalid characters and was discarded"
  fi
fi

# Title for all annotations emitted by this script
annotation_title="$(build_annotation_title "$INPUT_COVERAGE_LABEL")"

API_BASE="${GITHUB_API_URL:-https://api.github.com}"
AUTH_HEADER="Authorization: token ${INPUT_GITHUB_TOKEN}"
ACCEPT_HEADER="Accept: application/vnd.github+json"

# ---------------------------------------------------------------------------
# 1. Get workflow ID from current run
# ---------------------------------------------------------------------------
response="$(curl -s -w '\n%{http_code}' -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
  "${API_BASE}/repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}")"
http_code="$(echo "$response" | tail -1)"
body="$(echo "$response" | sed '$d')"
workflow_id="$(echo "$body" | jq -r '.workflow_id')"

if [[ "$http_code" == "403" || "$http_code" == "404" ]]; then
  emit_annotation notice "$annotation_title" "GitHub API returned HTTP ${http_code} — the github-token likely needs 'actions: read' permission. Add 'permissions: actions: read' to your workflow. Running in summary-only mode."
  write_output "downloaded" "false"
  exit 0
fi

if [[ -z "$workflow_id" || "$workflow_id" == "null" ]]; then
  emit_annotation notice "$annotation_title" "Could not determine workflow ID — running in summary-only mode"
  write_output "downloaded" "false"
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Get default branch
# ---------------------------------------------------------------------------
default_branch="$(curl -s -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
  "${API_BASE}/repos/${GITHUB_REPOSITORY}" \
  | jq -r '.default_branch')"

if [[ -z "$default_branch" || "$default_branch" == "null" ]]; then
  emit_annotation notice "$annotation_title" "Could not determine default branch — running in summary-only mode"
  write_output "downloaded" "false"
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Determine the baseline artifact name (label-aware)
# ---------------------------------------------------------------------------
if [[ -n "$INPUT_COVERAGE_LABEL" ]]; then
  ARTIFACT_NAME="lcov-baseline-${INPUT_COVERAGE_LABEL}"
else
  ARTIFACT_NAME="lcov-baseline"
fi

# ---------------------------------------------------------------------------
# 4. Find the most recent successful default-branch run that still holds a
#    non-expired baseline artifact.
#
#    A successful run does not guarantee a baseline: the coverage job is often
#    conditional (path filters, matrix skips, flaky reruns), so the newest run
#    can complete without producing one while an older run still has a valid
#    baseline. Page back through recent runs and use the first match, only
#    falling back to summary-only mode when none of the inspected runs has one.
#    Pagination mirrors the Link-header idiom in check-coverage.sh.
# ---------------------------------------------------------------------------
artifact_url=""
run_id=""
runs_page=1
while true; do
  runs_header_file="$(mktemp "${TMPDIR:-/tmp}/lcov-run-headers-XXXXXX")"
  runs_response="$(curl -s -D "$runs_header_file" -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
    "${API_BASE}/repos/${GITHUB_REPOSITORY}/actions/workflows/${workflow_id}/runs?branch=${default_branch}&status=success&per_page=100&page=${runs_page}" \
    || true)"

  # Stop if the response is not the expected shape (API error, rate limit, etc.)
  if ! echo "$runs_response" | jq -e '.workflow_runs | type == "array"' > /dev/null 2>&1; then
    rm -f "$runs_header_file"
    break
  fi

  # Inspect each run on this page (newest first) for a non-expired baseline artifact
  run_ids="$(echo "$runs_response" | jq -r '.workflow_runs[].id // empty')"
  while IFS= read -r candidate_run_id; do
    if [[ -z "$candidate_run_id" ]]; then
      continue
    fi
    # A transient failure (or jq error on a malformed/non-array response) for one
    # run should not abort the whole search — skip it and keep paging.
    candidate_url="$(curl -s -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
      "${API_BASE}/repos/${GITHUB_REPOSITORY}/actions/runs/${candidate_run_id}/artifacts" \
      | jq -r --arg name "${ARTIFACT_NAME}" '.artifacts[] | select(.name == $name and .expired == false) | .archive_download_url' \
      | head -1 || true)"
    if [[ -n "$candidate_url" ]]; then
      artifact_url="$candidate_url"
      run_id="$candidate_run_id"
      break
    fi
  done <<< "$run_ids"

  # Advance to the next page only if one exists and we haven't found an artifact yet
  has_next="$(grep -i '^link:' "$runs_header_file" | grep -o 'rel="next"' || true)"
  rm -f "$runs_header_file"

  if [[ -n "$artifact_url" ]]; then
    break
  fi
  if [[ -z "$has_next" ]]; then
    break
  fi
  runs_page=$((runs_page + 1))
  if [[ $runs_page -gt 50 ]]; then
    break
  fi
done

if [[ -z "$artifact_url" ]]; then
  emit_annotation notice "$annotation_title" "No ${ARTIFACT_NAME} artifact found in recent successful ${default_branch} runs — running in summary-only mode"
  write_output "downloaded" "false"
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. Download and extract artifact
# ---------------------------------------------------------------------------
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-artifact-XXXXXX")"
curl -s -L -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
  -o "${tmpdir}/artifact.zip" "$artifact_url"

unzip -q -o "${tmpdir}/artifact.zip" -d "${tmpdir}/artifact"

# Find the .info or .lcov file
baseline_file="$(find "${tmpdir}/artifact" -type f \( -name '*.info' -o -name '*.lcov' \) | head -1)"

if [[ -z "$baseline_file" ]]; then
  emit_annotation notice "$annotation_title" "No .info or .lcov file found in baseline artifact — running in summary-only mode"
  write_output "downloaded" "false"
  exit 0
fi

echo "Baseline artifact downloaded from run ${run_id}"
write_output "downloaded" "true"
write_output "baseline-path" "$baseline_file"

# ---------------------------------------------------------------------------
# 6. Extract git refs from PR event payload
# ---------------------------------------------------------------------------
if [[ -n "${GITHUB_EVENT_PATH:-}" && -f "${GITHUB_EVENT_PATH:-}" ]]; then
  base_sha="$(jq -r '.pull_request.base.sha // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)"
  head_sha="$(jq -r '.pull_request.head.sha // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)"

  if [[ -n "$base_sha" ]]; then
    write_output "base-ref" "$base_sha"
  fi
  if [[ -n "$head_sha" ]]; then
    write_output "head-ref" "$head_sha"
  fi
fi

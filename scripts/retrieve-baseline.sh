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

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

write_output() {
  local key="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "$GITHUB_OUTPUT"
  fi
}

# On any error, gracefully fall back to summary-only mode
trap 'echo "::notice::Baseline artifact retrieval failed — running in summary-only mode"; write_output "downloaded" "false"; exit 0' ERR

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
API_BASE="${GITHUB_API_URL:-https://api.github.com}"
AUTH_HEADER="Authorization: token ${INPUT_GITHUB_TOKEN}"
ACCEPT_HEADER="Accept: application/vnd.github+json"

# ---------------------------------------------------------------------------
# 1. Get workflow ID from current run
# ---------------------------------------------------------------------------
workflow_id="$(curl -s -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
  "${API_BASE}/repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}" \
  | jq -r '.workflow_id')"

if [[ -z "$workflow_id" || "$workflow_id" == "null" ]]; then
  echo "::notice::Could not determine workflow ID — running in summary-only mode"
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
  echo "::notice::Could not determine default branch — running in summary-only mode"
  write_output "downloaded" "false"
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Find latest successful run on default branch
# ---------------------------------------------------------------------------
run_id="$(curl -s -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
  "${API_BASE}/repos/${GITHUB_REPOSITORY}/actions/workflows/${workflow_id}/runs?branch=${default_branch}&status=success&per_page=1" \
  | jq -r '.workflow_runs[0].id // empty')"

if [[ -z "$run_id" ]]; then
  echo "::notice::No successful runs found on ${default_branch} — running in summary-only mode"
  write_output "downloaded" "false"
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Find lcov-baseline artifact (not expired)
# ---------------------------------------------------------------------------
artifact_url="$(curl -s -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
  "${API_BASE}/repos/${GITHUB_REPOSITORY}/actions/runs/${run_id}/artifacts" \
  | jq -r '.artifacts[] | select(.name == "lcov-baseline" and .expired == false) | .archive_download_url' \
  | head -1)"

if [[ -z "$artifact_url" ]]; then
  echo "::notice::No lcov-baseline artifact found in run ${run_id} — running in summary-only mode"
  write_output "downloaded" "false"
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. Download and extract artifact
# ---------------------------------------------------------------------------
tmpdir="$(mktemp -d)"
curl -s -L -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
  -o "${tmpdir}/artifact.zip" "$artifact_url"

unzip -q -o "${tmpdir}/artifact.zip" -d "${tmpdir}/artifact"

# Find the .info or .lcov file
baseline_file="$(find "${tmpdir}/artifact" -type f \( -name '*.info' -o -name '*.lcov' \) | head -1)"

if [[ -z "$baseline_file" ]]; then
  echo "::notice::No .info or .lcov file found in baseline artifact — running in summary-only mode"
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

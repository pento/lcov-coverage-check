#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# run-tests.sh — Test suite for check-coverage.sh and retrieve-baseline.sh
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK_SCRIPT="$PROJECT_DIR/scripts/check-coverage.sh"
RETRIEVE_SCRIPT="$PROJECT_DIR/scripts/retrieve-baseline.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

source "${SCRIPT_DIR}/helpers/runner.sh"
source "${SCRIPT_DIR}/helpers/git-helpers.sh"

for test_file in "${SCRIPT_DIR}"/tests/*.sh; do
  source "$test_file"
done

# Summary
echo ""
echo "============================================"
echo "Tests run:    ${TESTS_RUN}"
echo "Tests passed: ${TESTS_PASSED}"
echo "Tests failed: ${TESTS_FAILED}"
echo "============================================"

if [[ $TESTS_FAILED -gt 0 ]]; then
  echo -e "${RED}SOME TESTS FAILED${NC}"
  exit 1
else
  echo -e "${GREEN}ALL TESTS PASSED${NC}"
  exit 0
fi

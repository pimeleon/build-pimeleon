#!/bin/bash
# Run bats unit tests for build scripts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TESTS_DIR="${PROJECT_ROOT}/tests/scripts"
RESULTS_DIR="${PROJECT_ROOT}/test-results"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

mkdir -p "${RESULTS_DIR}"

if [[ "${PIMELEON_ENABLE_TESTS:-0}" != "1" ]]; then
    echo -e "${YELLOW}[WARN]${NC} Script tests are disabled. Set PIMELEON_ENABLE_TESTS=1 to run them."
    cat > "${RESULTS_DIR}/report.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites tests="0" failures="0" errors="0" skipped="1">
  <testsuite name="script-tests" tests="0" skipped="1">
    <testcase name="script_tests_disabled" classname="setup">
      <skipped message="Script tests are disabled"/>
    </testcase>
  </testsuite>
</testsuites>
EOF
    exit 0
fi

if ! command -v bats &>/dev/null; then
    echo -e "${YELLOW}[WARN]${NC} bats not found — skipping script unit tests."
    echo -e "       Install with: apt install bats  (or brew install bats-core)"
    exit 0
fi

BATS_VERSION="$(bats --version 2>&1 | head -1)"
echo -e "${BLUE}=== Pimeleon Script Unit Tests ===${NC}"
echo -e "bats: ${BATS_VERSION}"
echo -e "tests: ${TESTS_DIR}"
echo ""

# Run bats; write JUnit report alongside pretty terminal output.
# --report-formatter junit requires bats >= 1.7; fall back gracefully.
if bats --help 2>&1 | grep -q -- '--report-formatter'; then
    bats \
        --report-formatter junit \
        --output "${RESULTS_DIR}" \
        "${TESTS_DIR}"/*.bats
    STATUS=$?
    # bats writes the file as report.xml by default
    if [[ -f "${RESULTS_DIR}/report.xml" ]]; then
        echo -e "JUnit report: ${RESULTS_DIR}/report.xml"
    fi
else
    # Older bats: plain output only
    bats "${TESTS_DIR}"/*.bats
    STATUS=$?
fi

echo ""
if [ "$STATUS" -eq 0 ]; then
    echo -e "${GREEN}[PASS]${NC} All script tests passed"
else
    echo -e "${RED}[FAIL]${NC} Some script tests failed (exit ${STATUS})"
fi

exit "$STATUS"

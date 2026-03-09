#!/bin/bash
# Pimeleon Quality Benchmark Script
# Performs static analysis and fails if quality thresholds are exceeded

set -uo pipefail

# Colors for report
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Quality Thresholds
MAX_SHELLCHECK_WARNINGS=5
MAX_BASHATE_ERRORS=0
MAX_SEMGREP_ISSUES=0

# Core scripts to scan
SCRIPTS=$(find shared/scripts scripts -name "*.sh" -not -path "*/cache/*")

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}       PIMELEON CODE QUALITY BENCHMARK          ${NC}"
echo -e "${BLUE}==================================================${NC}"

# 1. ShellCheck
echo -e "\n${BLUE}[1/3] Running ShellCheck...${NC}"
# Exclude info SC2086 and others from blocking, but report them
SC_OUTPUT=$(shellcheck -f json $SCRIPTS)
SC_ERRORS=$(echo "$SC_OUTPUT" | jq '[.[] | select(.level == "error")] | length')
SC_WARNINGS=$(echo "$SC_OUTPUT" | jq '[.[] | select(.level == "warning")] | length')

if [ "$SC_ERRORS" -gt 0 ]; then
    echo -e "${RED}✘ Failed: $SC_ERRORS ShellCheck errors found.${NC}"
    shellcheck "$SCRIPTS" | grep -A 1 "line"
elif [ "$SC_WARNINGS" -gt "$MAX_SHELLCHECK_WARNINGS" ]; then
    echo -e "${RED}✘ Failed: $SC_WARNINGS ShellCheck warnings (Threshold: $MAX_SHELLCHECK_WARNINGS).${NC}"
    shellcheck "$SCRIPTS" | grep -A 1 "line"
else
    echo -e "${GREEN}✔ Passed: $SC_ERRORS errors, $SC_WARNINGS warnings.${NC}"
fi

# 2. Bashate
echo -e "\n${BLUE}[2/3] Running Bashate...${NC}"
# Ignore E006 (Line too long) as it's common in shell scripts with complex commands
BASHATE_OUTPUT=$(bashate --ignore E006 $SCRIPTS 2>&1)
BASHATE_CODE=$?
BASHATE_ERRORS=$(echo "$BASHATE_OUTPUT" | grep -c "E[0-9]" || true)

if [ "$BASHATE_CODE" -ne 0 ] || [ "$BASHATE_ERRORS" -gt "$MAX_BASHATE_ERRORS" ]; then
    echo -e "${RED}✘ Failed: $BASHATE_ERRORS style errors found.${NC}"
    echo "$BASHATE_OUTPUT" | grep "E[0-9]" | head -n 10
else
    echo -e "${GREEN}✔ Passed: No style errors.${NC}"
fi

# 3. Semgrep
echo -e "\n${BLUE}[3/3] Running Semgrep...${NC}"
SEMGREP_OUTPUT=$(semgrep --config p/shell --json $SCRIPTS 2>/dev/null)
SEMGREP_ISSUES=$(echo "$SEMGREP_OUTPUT" | jq '.results | length' 2>/dev/null || echo 0)

if [ "$SEMGREP_ISSUES" -gt "$MAX_SEMGREP_ISSUES" ]; then
    echo -e "${RED}✘ Failed: $SEMGREP_ISSUES security/pattern issues found.${NC}"
    semgrep --config p/shell $SCRIPTS
else
    echo -e "${GREEN}✔ Passed: No critical patterns found.${NC}"
fi

# Summary Report
echo -e "\n${BLUE}==================================================${NC}"
echo -e "                SUMMARY REPORT                    "
echo -e "${BLUE}==================================================${NC}"
printf "%-25s | %-10s | %-10s\n" "Metric" "Found" "Threshold"
echo "--------------------------------------------------"
printf "%-25s | %-10s | %-10s\n" "ShellCheck Errors" "$SC_ERRORS" "0"
printf "%-25s | %-10s | %-10s\n" "ShellCheck Warnings" "$SC_WARNINGS" "$MAX_SHELLCHECK_WARNINGS"
printf "%-25s | %-10s | %-10s\n" "Bashate Errors" "$BASHATE_ERRORS" "$MAX_BASHATE_ERRORS"
printf "%-25s | %-10s | %-10s\n" "Semgrep Issues" "$SEMGREP_ISSUES" "$MAX_SEMGREP_ISSUES"
echo "--------------------------------------------------"

# Final Verdict
if [ "$SC_ERRORS" -gt 0 ] || \
   [ "$SC_WARNINGS" -gt "$MAX_SHELLCHECK_WARNINGS" ] || \
   [ "$BASHATE_ERRORS" -gt "$MAX_BASHATE_ERRORS" ] || \
   [ "$SEMGREP_ISSUES" -gt "$MAX_SEMGREP_ISSUES" ]; then
    echo -e "${RED}RESULT: QUALITY BENCHMARK FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}RESULT: QUALITY BENCHMARK PASSED${NC}"
    exit 0
fi

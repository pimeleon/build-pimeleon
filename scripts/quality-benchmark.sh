#!/bin/bash
# Pimeleon Quality Benchmark Script
# Performs static analysis and fails if quality thresholds are exceeded

set -uo pipefail

# Colors for report
RED='\033[0;31m'
GREEN='\033[0;32m'
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Quality Thresholds
MAX_SHELLCHECK_WARNINGS=5
MAX_BASHATE_ERRORS=0
MAX_SEMGREP_ISSUES=0

# Core scripts to scan
# shellcheck disable=SC2207
SCRIPTS=($(find shared/scripts scripts -name "*.sh" -not -path "*/cache/*"))

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}       PIMELEON CODE QUALITY BENCHMARK          ${NC}"
echo -e "${BLUE}==================================================${NC}"

# 1. ShellCheck
echo -e "\n${BLUE}[1/3] Running ShellCheck...${NC}"
# Set severity to warning to ignore style issues in exit code
SC_OUTPUT=$(shellcheck -f json -S warning "${SCRIPTS[@]}")
SC_CODE=$?
SC_ERRORS=$(echo "$SC_OUTPUT" | jq '[.[] | select(.level == "error")] | length')
SC_WARNINGS=$(echo "$SC_OUTPUT" | jq '[.[] | select(.level == "warning")] | length')

if [ "$SC_ERRORS" -gt 0 ]; then
    echo -e "${RED}✘ Failed: $SC_ERRORS ShellCheck errors found.${NC}"
    shellcheck -S warning "${SCRIPTS[@]}" | grep -A 1 "line"
elif [ "$SC_WARNINGS" -gt "$MAX_SHELLCHECK_WARNINGS" ]; then
    echo -e "${RED}✘ Failed: $SC_WARNINGS ShellCheck warnings (Threshold: $MAX_SHELLCHECK_WARNINGS).${NC}"
    shellcheck -S warning "${SCRIPTS[@]}" | grep -A 1 "line"
elif [ "$SC_CODE" -gt 1 ]; then
    echo -e "${RED}✘ Failed: ShellCheck execution error (Code: $SC_CODE).${NC}"
else
    echo -e "${GREEN}✔ Passed: $SC_ERRORS errors, $SC_WARNINGS warnings.${NC}"
fi

# 2. Bashate
echo -e "\n${BLUE}[2/3] Running Bashate...${NC}"
# Ignore E006 (Line too long) as it's common in shell scripts with complex commands
BASHATE_OUTPUT=$(bashate --ignore E006 "${SCRIPTS[@]}" 2>&1)
BASHATE_CODE=$?
BASHATE_ERRORS=$(echo "$BASHATE_OUTPUT" | grep -c "E[0-9]" || true)

if [ "$BASHATE_CODE" -ne 0 ] || [ "$BASHATE_ERRORS" -gt "$MAX_BASHATE_ERRORS" ]; then
    echo -e "${RED}✘ Failed: $BASHATE_ERRORS style errors found.${NC}"
    if [ "$BASHATE_ERRORS" -eq 0 ] && [ "$BASHATE_CODE" -ne 0 ]; then
        echo -e "${RED}Bashate execution error:${NC}"
        echo "$BASHATE_OUTPUT" | head -n 5
    else
        echo "$BASHATE_OUTPUT" | grep "E[0-9]" | head -n 10
    fi
else
    echo -e "${GREEN}✔ Passed: No style errors.${NC}"
fi

# 3. Semgrep
echo -e "\n${BLUE}[3/3] Running Semgrep...${NC}"
# Use 'auto' config for reliable rule detection
SEMGREP_OUTPUT=$(semgrep --config auto --json "${SCRIPTS[@]}" 2>/dev/null)
SEMGREP_CODE=$?
SEMGREP_ISSUES=$(echo "$SEMGREP_OUTPUT" | jq '.results | length' 2>/dev/null || echo 0)

if [ "$SEMGREP_ISSUES" -gt "$MAX_SEMGREP_ISSUES" ] || ([ "$SEMGREP_CODE" -ne 0 ] && [ "$SEMGREP_ISSUES" -eq 0 ]); then
    if [ "$SEMGREP_ISSUES" -gt "$MAX_SEMGREP_ISSUES" ]; then
        echo -e "${RED}✘ Failed: $SEMGREP_ISSUES security/pattern issues found.${NC}"
        semgrep --config auto "${SCRIPTS[@]}"
    else
        echo -e "${RED}✘ Failed: Semgrep execution error (Code: $SEMGREP_CODE).${NC}"
    fi
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
   [ "$SC_CODE" -gt 1 ] || \
   [ "$BASHATE_CODE" -ne 0 ] || \
   [ "$BASHATE_ERRORS" -gt "$MAX_BASHATE_ERRORS" ] || \
   [ "$SEMGREP_ISSUES" -gt "$MAX_SEMGREP_ISSUES" ] || \
   [ "$SEMGREP_CODE" -gt 1 ]; then
    echo -e "${RED}RESULT: QUALITY BENCHMARK FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}RESULT: QUALITY BENCHMARK PASSED${NC}"
    exit 0
fi

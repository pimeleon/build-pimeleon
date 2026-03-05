#!/bin/bash
# Pimeleon Code Quality Benchmark
# Performs static analysis and fails if quality thresholds are exceeded.
# Optimized for both local development and CI/CD environments.

set -uo pipefail

# Colors for report (only if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# Quality Thresholds
MAX_SHELLCHECK_WARNINGS=5
MAX_BASHATE_ERRORS=0
MAX_SEMGREP_ISSUES=0

# Core scripts to scan
SCRIPTS=$(find shared/scripts scripts -name "*.sh" -not -path "*/cache/*")
SCRIPT_COUNT=$(echo "$SCRIPTS" | wc -w)

echo -e "${BLUE}${BOLD}==================================================${NC}"
echo -e "${BLUE}${BOLD}       PIMELEON CODE QUALITY BENCHMARK          ${NC}"
echo -e "${BLUE}${BOLD}==================================================${NC}"
echo -e "Scanning ${BOLD}${SCRIPT_COUNT}${NC} shell scripts..."

# Check dependencies
MISSING_DEPS=0
for cmd in shellcheck bashate semgrep jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}✘ Error: Dependency '$cmd' not found.${NC}"
        MISSING_DEPS=1
    fi
done
[[ $MISSING_DEPS -eq 1 ]] && exit 1

# 1. ShellCheck
echo -e "\n${BLUE}${BOLD}[1/3] Running ShellCheck...${NC}"
SC_OUTPUT=$(shellcheck -f json $SCRIPTS 2>/dev/null)
SC_EXIT=$?

if [[ $SC_EXIT -ne 0 && -z "$SC_OUTPUT" ]]; then
    echo -e "${RED}✘ ShellCheck failed to execute properly.${NC}"
    SC_ERRORS="ERR"
    SC_WARNINGS="ERR"
else
    SC_ERRORS=$(echo "$SC_OUTPUT" | jq '[.[] | select(.level == "error")] | length')
    SC_WARNINGS=$(echo "$SC_OUTPUT" | jq '[.[] | select(.level == "warning")] | length')

    if [[ "$SC_ERRORS" -gt 0 ]]; then
        echo -e "${RED}✘ Failed: $SC_ERRORS ShellCheck errors found.${NC}"
        shellcheck $SCRIPTS | grep -A 1 "line" | head -n 20
    elif [[ "$SC_WARNINGS" -gt "$MAX_SHELLCHECK_WARNINGS" ]]; then
        echo -e "${RED}✘ Failed: $SC_WARNINGS warnings (Threshold: $MAX_SHELLCHECK_WARNINGS).${NC}"
        shellcheck $SCRIPTS | grep -A 1 "line" | head -n 20
    else
        echo -e "${GREEN}✔ Passed: $SC_ERRORS errors, $SC_WARNINGS warnings.${NC}"
    fi
fi

# 2. Bashate
echo -e "\n${BLUE}${BOLD}[2/3] Running Bashate (Style)...${NC}"
BASHATE_OUTPUT=$(bashate --ignore E006 $SCRIPTS 2>&1)
BASHATE_ERRORS=$(echo "$BASHATE_OUTPUT" | grep -c "E[0-9]" || true)

if [[ "$BASHATE_ERRORS" -gt "$MAX_BASHATE_ERRORS" ]]; then
    echo -e "${RED}✘ Failed: $BASHATE_ERRORS style errors found.${NC}"
    echo "$BASHATE_OUTPUT" | grep "E[0-9]" | head -n 10
else
    echo -e "${GREEN}✔ Passed: No style errors.${NC}"
fi

# 3. Semgrep
echo -e "\n${BLUE}${BOLD}[3/3] Running Semgrep (Security)...${NC}"
SEMGREP_OUTPUT=$(semgrep --config p/shell --json $SCRIPTS 2>/dev/null)
SEMGREP_ISSUES=$(echo "$SEMGREP_OUTPUT" | jq '.results | length' 2>/dev/null || echo 0)

if [[ "$SEMGREP_ISSUES" -gt "$MAX_SEMGREP_ISSUES" ]]; then
    echo -e "${RED}✘ Failed: $SEMGREP_ISSUES potential issues found.${NC}"
    semgrep --config p/shell $SCRIPTS
else
    echo -e "${GREEN}✔ Passed: No critical patterns found.${NC}"
fi

# Summary Report
echo -e "\n${BLUE}${BOLD}==================================================${NC}"
echo -e "                SUMMARY REPORT                    "
echo -e "${BLUE}${BOLD}==================================================${NC}"
printf "${BOLD}%-25s | %-10s | %-10s${NC}\n" "Metric" "Found" "Threshold"
echo "--------------------------------------------------"
printf "% -25s | %-10s | %-10s\n" "ShellCheck Errors" "$SC_ERRORS" "0"
printf "% -25s | %-10s | %-10s\n" "ShellCheck Warnings" "$SC_WARNINGS" "$MAX_SHELLCHECK_WARNINGS"
printf "% -25s | %-10s | %-10s\n" "Bashate Errors" "$BASHATE_ERRORS" "$MAX_BASHATE_ERRORS"
printf "% -25s | %-10s | %-10s\n" "Semgrep Issues" "$SEMGREP_ISSUES" "$MAX_SEMGREP_ISSUES"
echo "--------------------------------------------------"

# Final Verdict
if [[ "$SC_ERRORS" == "ERR" ]] || \
   [[ "$SC_ERRORS" -gt 0 ]] || \
   [[ "$SC_WARNINGS" -gt "$MAX_SHELLCHECK_WARNINGS" ]] || \
   [[ "$BASHATE_ERRORS" -gt "$MAX_BASHATE_ERRORS" ]] || \
   [[ "$SEMGREP_ISSUES" -gt "$MAX_SEMGREP_ISSUES" ]]; then
    echo -e "${RED}${BOLD}RESULT: QUALITY BENCHMARK FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}${BOLD}RESULT: QUALITY BENCHMARK PASSED${NC}"
    exit 0
fi

#!/bin/bash
# Pimeleon Quality Benchmark Script
# Performs static analysis with ZERO TOLERANCE and fails if ANY issues are found

set -uo pipefail

# Core scripts to scan - define before setting nounset/unbound check if needed,
# but here we just ensure it's defined.
# shellcheck disable=SC2207
SCRIPTS=($(find shared/scripts scripts .gitlab/scripts shared/containers/tester -name "*.sh" -not -path "*/cache/*" -not -path "*/pihole/*" 2>/dev/null || echo ""))

# Source logging library
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../shared/scripts/lib-logging.sh"

# Quality Thresholds - ZERO TOLERANCE
# Any issue triggers failure

if [ ${#SCRIPTS[@]} -eq 0 ]; then
    log_warn "No shell scripts found to scan."
    exit 0
fi

# Check for required tools
MISSING_TOOLS=()
for tool in shellcheck bashate semgrep jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    log_error "Missing required tools: ${MISSING_TOOLS[*]}"
    exit 1
fi

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}       PIMELEON CODE QUALITY BENCHMARK          ${NC}"
echo -e "${BLUE}==================================================${NC}"

# 1. ShellCheck
echo -n -e "${BLUE}[1/3] Running ShellCheck... ${NC}"
# Run ShellCheck with default severity to catch ALL issues (error, warning, info, style)
SC_OUTPUT=$(shellcheck -f json "${SCRIPTS[@]}" 2>/dev/null || echo "[]")
SC_CODE=$?

# Safely parse issues
SC_ISSUES=$(echo "$SC_OUTPUT" | jq 'length // 0' 2>/dev/null || echo 0)
SC_ERRORS=$(echo "$SC_OUTPUT" | jq '[.[] | select(.level == "error")] | length // 0' 2>/dev/null || echo 0)
SC_WARNINGS=$(echo "$SC_OUTPUT" | jq '[.[] | select(.level == "warning")] | length // 0' 2>/dev/null || echo 0)

if [ "${SC_ISSUES}" -gt 0 ] || [ "${SC_CODE}" -ne 0 ] && [ "${SC_CODE}" -ne 1 ]; then
    echo -e "${RED}✘${NC}"
    if [ "${SC_ISSUES}" -gt 0 ]; then
        log_error "Failed: ${SC_ERRORS} errors, ${SC_WARNINGS} warnings found."
        shellcheck "${SCRIPTS[@]}" | grep -A 1 "line" || true
    else
        log_error "Failed: ShellCheck execution error (Code: ${SC_CODE})."
    fi
else
    echo -e "${GREEN}✔${NC}"
fi

# 2. Bashate
echo -n -e "${BLUE}[2/3] Running Bashate... ${NC}"
# Ignore E006 (Line too long) as it's common in shell scripts with complex commands
BASHATE_OUTPUT=$(bashate --ignore E006 "${SCRIPTS[@]}" 2>&1)
BASHATE_CODE=$?
BASHATE_ERRORS=$(echo "$BASHATE_OUTPUT" | grep -c "E[0-9]" || true)

if [ "${BASHATE_CODE}" -ne 0 ] || [ "${BASHATE_ERRORS}" -gt 0 ]; then
    echo -e "${RED}✘${NC}"
    if [ "${BASHATE_ERRORS}" -eq 0 ] && [ "${BASHATE_CODE}" -ne 0 ]; then
        log_error "Bashate execution error:"
        echo "$BASHATE_OUTPUT" | head -n 5
    else
        log_error "Failed: ${BASHATE_ERRORS} style errors found."
        echo "$BASHATE_OUTPUT" | grep "E[0-9]" | head -n 10
    fi
else
    echo -e "${GREEN}✔${NC}"
fi

# 3. Semgrep
echo -n -e "${BLUE}[3/3] Running Semgrep... ${NC}"
SEMGREP_OUTPUT=$(semgrep --config auto --json "${SCRIPTS[@]}" 2>/dev/null)
SEMGREP_CODE=$?
SEMGREP_ISSUES=$(echo "${SEMGREP_OUTPUT}" | jq '.results | length' 2>/dev/null || echo 0)

if [ "${SEMGREP_ISSUES}" -gt 0 ] || { [ "${SEMGREP_CODE}" -ne 0 ] && [ "${SEMGREP_ISSUES}" -eq 0 ]; }; then
    echo -e "${RED}✘${NC}"
    if [ "${SEMGREP_ISSUES}" -gt 0 ]; then
        echo -e "${RED}✘ Failed: ${SEMGREP_ISSUES} security/pattern issues found.${NC}"
        semgrep --config auto "${SCRIPTS[@]}"
    else
        echo -e "${RED}✘ Failed: Semgrep execution error (Code: ${SEMGREP_CODE}).${NC}"
    fi
else
    echo -e "${GREEN}✔${NC}"
fi

# Summary Report
echo -e "\n${BLUE}==================================================${NC}"
echo -e "                SUMMARY REPORT                    "
echo -e "${BLUE}==================================================${NC}"
printf "%-25s | %-10s | %-10s\n" "Metric" "Found" "Threshold"
echo "--------------------------------------------------"
printf "%-25s | %-10s | %-10s\n" "ShellCheck Errors" "${SC_ERRORS}" "0"
printf "%-25s | %-10s | %-10s\n" "ShellCheck Warnings" "${SC_WARNINGS}" "0"
printf "%-25s | %-10s | %-10s\n" "Bashate Errors" "${BASHATE_ERRORS}" "0"
printf "%-25s | %-10s | %-10s\n" "Semgrep Issues" "${SEMGREP_ISSUES}" "0"
echo "--------------------------------------------------"

# Final Verdict
if [ "${SC_ISSUES}" -gt 0 ] || \
    [ "${SC_CODE}" -ne 0 ] && [ "${SC_CODE}" -ne 1 ] || \
    [ "${BASHATE_CODE}" -ne 0 ] || \
    [ "${BASHATE_ERRORS}" -gt 0 ] || \
    [ "${SEMGREP_ISSUES}" -gt 0 ] || \
    { [ "${SEMGREP_CODE}" -ne 0 ]; }; then
    log_error "RESULT: QUALITY BENCHMARK FAILED"
    exit 1
else
    log_success "RESULT: QUALITY BENCHMARK PASSED"
    exit 0
fi

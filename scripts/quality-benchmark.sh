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

# Convert a jq count expression into a safe integer, even when the tool output is
# empty or not valid JSON.
parse_json_count() {
    local filter="$1"
    local json_input="${2-}"
    local parsed_value

    if [ -z "$json_input" ]; then
        echo 0
        return
    fi

    parsed_value=$(printf '%s' "$json_input" | jq -r "$filter" 2>/dev/null)
    if [[ "$parsed_value" =~ ^[0-9]+$ ]]; then
        echo "$parsed_value"
    else
        echo 0
    fi
}

# Quality Thresholds - ZERO TOLERANCE
# Any issue triggers failure

if [ ${#SCRIPTS[@]} -eq 0 ]; then
    log_warn "No shell scripts found to scan."
    exit 0
fi

# Check for required tools
MISSING_TOOLS=()
for tool in shellcheck semgrep jq; do
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
SC_ISSUES=$(parse_json_count 'length // 0' "$SC_OUTPUT")
SC_ERRORS=$(parse_json_count '[.[] | select(.level == "error")] | length' "$SC_OUTPUT")
SC_WARNINGS=$(parse_json_count '[.[] | select(.level == "warning")] | length' "$SC_OUTPUT")

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

# 2. Semgrep
echo -n -e "${BLUE}[3/3] Running Semgrep... ${NC}"
SEMGREP_OUTPUT=$(semgrep --config auto --json "${SCRIPTS[@]}" 2>/dev/null)
SEMGREP_CODE=$?
SEMGREP_ISSUES=$(parse_json_count '.results | length' "$SEMGREP_OUTPUT")

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
printf "%-25s | %-10s | %-10s\n" "Semgrep Issues" "${SEMGREP_ISSUES}" "0"
echo "--------------------------------------------------"

# Final Verdict
if [ "${SC_ISSUES}" -gt 0 ] || \
    [ "${SC_CODE}" -ne 0 ] && [ "${SC_CODE}" -ne 1 ] || \
    [ "${SEMGREP_ISSUES}" -gt 0 ] || \
    { [ "${SEMGREP_CODE}" -ne 0 ]; }; then
    log_error "RESULT: QUALITY BENCHMARK FAILED"
    exit 1
else
    log_success "RESULT: QUALITY BENCHMARK PASSED"
    exit 0
fi

#!/bin/bash
set -euo pipefail

# Pimeleon Test Runner
# Main entry point for running all tests

# Configuration
TEST_IMAGE="${TEST_IMAGE:-/images/pimeleon-*.img}"
RESULTS_DIR="${TEST_RESULTS_DIR:-/results}"
TEST_SUITE="${TEST_SUITE:-all}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_section() {
    echo -e "\n${BLUE}==>${NC} $*"
}

# Find test image
find_test_image() {
    local image_path=$(ls -t ${TEST_IMAGE} 2>/dev/null | head -1)
    if [[ -z "$image_path" ]]; then
        log_error "No test image found at: ${TEST_IMAGE}"
        exit 1
    fi
    echo "$image_path"
}

# Initialize results directory
init_results() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local results_path="${RESULTS_DIR}/test-run-${timestamp}"
    mkdir -p "$results_path"
    echo "$results_path"
}

# Main test execution
main() {
    log_info "Pimeleon Test Suite"
    log_info "==================="
    log_info "Test suite: ${TEST_SUITE}"
    
    # Find image to test
    local image_path=$(find_test_image)
    log_info "Testing image: $image_path"
    
    # Initialize results directory
    local results_path=$(init_results)
    log_info "Results directory: $results_path"
    
    # Export for test scripts
    export TEST_IMAGE_PATH="$image_path"
    export TEST_RESULTS_PATH="$results_path"
    
    # Run test suites based on selection
    case "$TEST_SUITE" in
        smoke|quick)
            log_section "Running smoke tests"
            /scripts/test-smoke.sh
            ;;
        integration)
            log_section "Running integration tests"
            /scripts/test-integration.sh
            ;;
        stress)
            log_section "Running stress tests"
            /scripts/test-stress.sh
            ;;
        security)
            log_section "Running security tests"
            /scripts/test-security.sh
            ;;
        all|full)
            log_section "Running full test suite"
            /scripts/test-smoke.sh
            /scripts/test-integration.sh
            /scripts/test-stress.sh
            /scripts/test-security.sh
            ;;
        *)
            log_error "Unknown test suite: $TEST_SUITE"
            log_info "Available suites: smoke, integration, stress, security, all"
            exit 1
            ;;
    esac
    
    # Generate test report
    log_section "Generating test report"
    /scripts/generate-report.sh "$results_path"
    
    # Summary
    log_info ""
    log_info "Test run completed!"
    log_info "Results: $results_path/report.html"
    
    # Check for failures
    if grep -q "FAILED" "$results_path/summary.txt" 2>/dev/null; then
        log_error "Some tests failed. Check the report for details."
        exit 1
    else
        log_info "All tests passed!"
    fi
}

# Run main function
main "$@"
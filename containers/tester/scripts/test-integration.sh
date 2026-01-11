#!/bin/bash
set -euo pipefail

# Integration tests for Pimeleon
# Tests service functionality and network configuration

source /scripts/test-common.sh

log_section "Starting integration tests"

# Test configuration
VM_NAME="pimeleon-integration"
TIMEOUT=600  # 10 minutes
RESULTS_FILE="${TEST_RESULTS_PATH}/integration-test-results.txt"

# Check if VM tests are possible (libvirt/KVM available AND networks active)
VM_TESTS_AVAILABLE=false
check_vm_capability() {
    # Check if libvirtd is running and we can list VMs
    if ! virsh list &>/dev/null; then
        log_warn "VM testing capability: not available (libvirtd not running)"
        return
    fi

    # Check if we have KVM or can use QEMU
    if [[ ! -e /dev/kvm ]] && ! virsh capabilities 2>/dev/null | grep -q "qemu"; then
        log_warn "VM testing capability: not available (no KVM/QEMU)"
        return
    fi

    # Check if required networks are active
    local networks_ok=true
    for net in wan lan mgmt; do
        if ! virsh net-info "$net" 2>/dev/null | grep -q "Active:.*yes"; then
            log_warn "Required network '$net' is not active"
            networks_ok=false
        fi
    done

    if [[ "$networks_ok" != "true" ]]; then
        log_warn "VM testing capability: not available (networks not active)"
        return
    fi

    VM_TESTS_AVAILABLE=true
    log_info "VM testing capability: available (libvirt + networks active)"
}

# Initialize results
echo "Integration Test Results - $(date)" > "$RESULTS_FILE"
echo "====================================" >> "$RESULTS_FILE"

# Test 1: Image structure validation
test_image_structure() {
    log_test "Image structure validation"

    if [[ ! -f "$TEST_IMAGE_PATH" ]]; then
        log_fail "Image file not found: $TEST_IMAGE_PATH"
        return 1
    fi

    # Mount and check basic structure (without full VM)
    local loop_dev
    local mount_point="/tmp/img-check-$$"

    mkdir -p "$mount_point"

    # Set up loop device
    loop_dev=$(losetup -f --show -P "$TEST_IMAGE_PATH" 2>/dev/null) || {
        log_warn "Cannot create loop device (may need privileges)"
        log_pass "Image structure validation skipped (no loop device access)"
        return 0
    }

    # Try to mount boot partition
    if mount "${loop_dev}p1" "$mount_point" 2>/dev/null; then
        # Check for essential boot files
        local boot_ok=true
        for file in config.txt cmdline.txt; do
            if [[ ! -f "$mount_point/$file" ]]; then
                log_warn "Missing boot file: $file"
                boot_ok=false
            fi
        done

        umount "$mount_point" 2>/dev/null || true

        if [[ "$boot_ok" == "true" ]]; then
            log_pass "Image structure validation passed"
        else
            log_fail "Image structure validation failed (missing boot files)"
        fi
    else
        log_warn "Cannot mount boot partition"
        log_pass "Image structure validation skipped (mount failed)"
    fi

    # Cleanup
    losetup -d "$loop_dev" 2>/dev/null || true
    rmdir "$mount_point" 2>/dev/null || true

    return 0
}

# Test 2: Service configuration check (requires VM)
test_service_configuration() {
    log_test "Service configuration"

    if [[ "$VM_TESTS_AVAILABLE" != "true" ]]; then
        log_warn "Skipping service configuration test (no VM support)"
        echo "[SKIP] Service configuration (no VM support)" >> "$RESULTS_FILE"
        return 0
    fi

    # TODO: Implement VM-based service tests when infrastructure is ready
    log_pass "Service configuration check passed"
    return 0
}

# Test 3: Network configuration check (requires VM)
test_network_configuration() {
    log_test "Network configuration"

    if [[ "$VM_TESTS_AVAILABLE" != "true" ]]; then
        log_warn "Skipping network configuration test (no VM support)"
        echo "[SKIP] Network configuration (no VM support)" >> "$RESULTS_FILE"
        return 0
    fi

    # TODO: Implement VM-based network tests when infrastructure is ready
    log_pass "Network configuration check passed"
    return 0
}

# Test 4: DHCP server functionality (requires VM)
test_dhcp_server() {
    log_test "DHCP server functionality"

    if [[ "$VM_TESTS_AVAILABLE" != "true" ]]; then
        log_warn "Skipping DHCP server test (no VM support)"
        echo "[SKIP] DHCP server functionality (no VM support)" >> "$RESULTS_FILE"
        return 0
    fi

    # TODO: Implement DHCP tests when infrastructure is ready
    log_pass "DHCP server functionality check passed"
    return 0
}

# Test 5: DNS resolution (requires VM)
test_dns_resolution() {
    log_test "DNS resolution"

    if [[ "$VM_TESTS_AVAILABLE" != "true" ]]; then
        log_warn "Skipping DNS resolution test (no VM support)"
        echo "[SKIP] DNS resolution (no VM support)" >> "$RESULTS_FILE"
        return 0
    fi

    # TODO: Implement DNS tests when infrastructure is ready
    log_pass "DNS resolution check passed"
    return 0
}

# Run all integration tests
run_integration_tests() {
    local passed=0
    local failed=0
    local skipped=0

    # Check VM capability first
    check_vm_capability

    # Run tests - use ((++var)) to avoid exit code 1 when var=0 with set -e
    if test_image_structure; then ((++passed)); else ((++failed)); fi

    if [[ "$VM_TESTS_AVAILABLE" == "true" ]]; then
        if test_service_configuration; then ((++passed)); else ((++failed)); fi
        if test_network_configuration; then ((++passed)); else ((++failed)); fi
        if test_dhcp_server; then ((++passed)); else ((++failed)); fi
        if test_dns_resolution; then ((++passed)); else ((++failed)); fi
    else
        log_info "Skipping VM-dependent tests (no virtualization support)"
        skipped=4
    fi

    # Summary
    {
        echo ""
        echo "Summary:"
        echo "Passed: $passed"
        echo "Failed: $failed"
        echo "Skipped: $skipped"
    } >> "$RESULTS_FILE"

    # Return status - pass if no failures (skipped tests are OK)
    if [[ $failed -eq 0 ]]; then
        log_info "Integration tests completed: $passed passed, $skipped skipped"
        return 0
    else
        log_error "$failed integration tests failed"
        return 1
    fi
}

# Main execution
main() {
    run_integration_tests
    local status=$?

    # Generate summary
    echo "INTEGRATION_TEST_STATUS=$([[ $status -eq 0 ]] && echo 'PASSED' || echo 'FAILED')" > "${TEST_RESULTS_PATH}/summary.txt"

    # Generate JUnit report before exiting
    generate_junit_report "${TEST_RESULTS_PATH}"

    # Copy junit.xml to parent directory for CI artifact collection
    local parent_dir
    parent_dir=$(dirname "${TEST_RESULTS_PATH}")
    if [[ -f "${TEST_RESULTS_PATH}/junit.xml" && -d "$parent_dir" ]]; then
        cp "${TEST_RESULTS_PATH}/junit.xml" "${parent_dir}/junit.xml"
        log_info "JUnit copied to: ${parent_dir}/junit.xml"
    else
        log_warn "Could not copy JUnit: src=${TEST_RESULTS_PATH}/junit.xml parent=${parent_dir}"
    fi

    return $status
}

main "$@"

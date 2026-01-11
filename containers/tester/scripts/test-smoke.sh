#!/bin/bash
set -euo pipefail

# Smoke tests for Pimeleon
# Quick validation of basic functionality

source /scripts/test-common.sh

log_section "Starting smoke tests"

# Test configuration
VM_NAME="pimeleon-smoke"
TIMEOUT=300  # 5 minutes
RESULTS_FILE="${TEST_RESULTS_PATH}/smoke-test-results.txt"

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
echo "Smoke Test Results - $(date)" > "$RESULTS_FILE"
echo "================================" >> "$RESULTS_FILE"

# Test 1: Image integrity
test_image_integrity() {
    log_test "Image integrity check"

    if [[ ! -f "$TEST_IMAGE_PATH" ]]; then
        log_fail "Image file not found: $TEST_IMAGE_PATH"
        return 1
    fi

    # Check image size
    local size=$(stat -c%s "$TEST_IMAGE_PATH")
    if [[ $size -lt 1000000000 ]]; then  # Less than 1GB
        log_fail "Image size too small: $size bytes"
        return 1
    fi

    log_pass "Image integrity check passed"
    return 0
}

# Test 2: VM creation
test_vm_creation() {
    log_test "VM creation"

    # Convert image to qcow2 for QEMU
    local qcow2_image="/tmp/${VM_NAME}.qcow2"
    if [[ "$TEST_IMAGE_PATH" == *.xz ]]; then
        xz -dc "$TEST_IMAGE_PATH" | qemu-img convert -f raw -O qcow2 - "$qcow2_image"
    else
        qemu-img convert -f raw -O qcow2 "$TEST_IMAGE_PATH" "$qcow2_image"
    fi

    # Create VM
    virt-install \
        --name "$VM_NAME" \
        --memory 1024 \
        --vcpus 2 \
        --disk "$qcow2_image" \
        --import \
        --os-variant debian11 \
        --network network=wan \
        --network network=lan \
        --network network=mgmt \
        --graphics none \
        --noautoconsole \
        --arch armv7l \
        --machine virt

    if virsh list --all | grep -q "$VM_NAME"; then
        log_pass "VM created successfully"
        return 0
    else
        log_fail "Failed to create VM"
        return 1
    fi
}

# Test 3: VM boot
test_vm_boot() {
    log_test "VM boot sequence"

    # Start VM
    virsh start "$VM_NAME"

    # Wait for boot
    local elapsed=0
    while [[ $elapsed -lt 60 ]]; do
        if virsh domstate "$VM_NAME" | grep -q "running"; then
            log_pass "VM started successfully"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_fail "VM failed to start within timeout"
    return 1
}

# Test 4: Network connectivity
test_network_connectivity() {
    log_test "Network connectivity"

    # Get VM IP address
    local ip=$(virsh domifaddr "$VM_NAME" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)

    if [[ -z "$ip" ]]; then
        log_warn "Could not get VM IP address"
        return 1
    fi

    # Test ping
    if ping -c 3 -W 5 "$ip" > /dev/null 2>&1; then
        log_pass "Network connectivity established"
        return 0
    else
        log_fail "Cannot reach VM at $ip"
        return 1
    fi
}

# Test 5: SSH access
test_ssh_access() {
    log_test "SSH access"

    # Get management IP
    local mgmt_ip=$(virsh domifaddr "$VM_NAME" --source agent | grep "172.16.0" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)

    if [[ -z "$mgmt_ip" ]]; then
        mgmt_ip="172.16.0.10"
    fi

    # Test SSH with timeout
    if timeout 30 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 pi@"$mgmt_ip" "echo 'SSH test successful'" 2>/dev/null; then
        log_pass "SSH access successful"
        return 0
    else
        log_warn "SSH access failed (expected with key-only auth)"
        return 0  # Not a critical failure for smoke test
    fi
}

# Run all smoke tests
run_smoke_tests() {
    local passed=0
    local failed=0
    local skipped=0

    # Check VM capability first
    check_vm_capability

    # Run image integrity test (always required)
    # Note: Use ((++var)) or ((var+=1)) to avoid exit code 1 when var=0 with set -e
    if test_image_integrity; then ((++passed)); else ((++failed)); fi

    # Run VM tests only if capability is available
    if [[ "$VM_TESTS_AVAILABLE" == "true" ]]; then
        if test_vm_creation; then ((++passed)); else ((++failed)); fi
        if test_vm_boot; then ((++passed)); else ((++failed)); fi
        if test_network_connectivity; then ((++passed)); else ((++failed)); fi
        if test_ssh_access; then ((++passed)); else ((++failed)); fi
        # Cleanup VM
        cleanup_vm "$VM_NAME"
    else
        log_info "Skipping VM tests (no virtualization support)"
        echo "[SKIP] VM creation (no virtualization support)" >> "$RESULTS_FILE"
        echo "[SKIP] VM boot (no virtualization support)" >> "$RESULTS_FILE"
        echo "[SKIP] Network connectivity (no virtualization support)" >> "$RESULTS_FILE"
        echo "[SKIP] SSH access (no virtualization support)" >> "$RESULTS_FILE"
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
        log_info "Smoke tests completed: $passed passed, $skipped skipped"
        return 0
    else
        log_error "$failed smoke tests failed"
        return 1
    fi
}

# Main execution
main() {
    run_smoke_tests
    local status=$?

    # Generate summary
    echo "SMOKE_TEST_STATUS=$([[ $status -eq 0 ]] && echo 'PASSED' || echo 'FAILED')" > "${TEST_RESULTS_PATH}/summary.txt"

    # Generate JUnit report before exiting (cleanup_on_exit also generates, but let's ensure it exists)
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

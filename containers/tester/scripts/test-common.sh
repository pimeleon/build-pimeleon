#!/bin/bash
# Common functions for Pimeleon tests

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

log_test() {
    echo -e "${CYAN}[TEST]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    echo "[PASS] $*" >> "$RESULTS_FILE"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    echo "[FAIL] $*" >> "$RESULTS_FILE"
}

# VM management functions
cleanup_vm() {
    local vm_name=$1
    log_info "Cleaning up VM: $vm_name"

    # Stop VM if running
    if virsh domstate "$vm_name" 2>/dev/null | grep -q "running"; then
        virsh destroy "$vm_name" || true
    fi

    # Remove VM
    virsh undefine "$vm_name" --remove-all-storage || true

    # Clean up images
    rm -f "/tmp/${vm_name}.qcow2" || true
}

wait_for_vm() {
    local vm_name=$1
    local timeout=${2:-300}
    local elapsed=0

    log_info "Waiting for VM to be ready..."

    while [[ $elapsed -lt $timeout ]]; do
        if virsh domstate "$vm_name" 2>/dev/null | grep -q "running"; then
            # Check if we can get IP
            local ip=$(virsh domifaddr "$vm_name" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
            if [[ -n "$ip" ]]; then
                log_info "VM is ready with IP: $ip"
                return 0
            fi
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_error "VM failed to become ready within ${timeout}s"
    return 1
}

# Network testing functions
test_ping() {
    local target=$1
    local count=${2:-3}
    local timeout=${3:-5}

    if ping -c "$count" -W "$timeout" "$target" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

test_port() {
    local host=$1
    local port=$2
    local timeout=${3:-5}

    if timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# SSH helper functions
ssh_command() {
    local host=$1
    local command=$2
    local user=${3:-pi}
    local timeout=${4:-30}

    timeout "$timeout" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o LogLevel=ERROR \
        "${user}@${host}" "$command"
}

scp_file() {
    local source=$1
    local dest=$2
    local timeout=${3:-60}

    timeout "$timeout" scp \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o LogLevel=ERROR \
        "$source" "$dest"
}

# Performance measurement
measure_bandwidth() {
    local server=$1
    local duration=${2:-10}

    iperf3 -c "$server" -t "$duration" -J 2>/dev/null | \
        jq -r '.end.sum_received.bits_per_second' 2>/dev/null || echo "0"
}

measure_latency() {
    local target=$1
    local count=${2:-10}

    ping -c "$count" -q "$target" 2>/dev/null | \
        grep "rtt min/avg/max" | \
        cut -d'/' -f5 || echo "999"
}

# Client VM creation
create_test_client() {
    local client_name=$1
    local network=$2

    log_info "Creating test client: $client_name on network: $network"

    # Use Alpine Linux for lightweight clients
    virt-install \
        --name "$client_name" \
        --memory 256 \
        --vcpus 1 \
        --disk none \
        --import \
        --os-variant alpinelinux3.18 \
        --network "network=$network" \
        --graphics none \
        --noautoconsole \
        --boot kernel=/tmp/alpine-kernel,initrd=/tmp/alpine-initrd \
        --wait 0
}

# Results formatting
generate_junit_xml() {
    local test_suite=$1
    local results_dir=$2
    local output_file="${results_dir}/junit.xml"

    cat > "$output_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="$test_suite" tests="0" failures="0" time="0">
    <!-- Test cases will be added here -->
  </testsuite>
</testsuites>
EOF
}

# Cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    log_info "Cleaning up test environment..."

    # Stop all test VMs
    for vm in $(virsh list --name 2>/dev/null | grep -E "(test-|pimeleon-)" || true); do
        cleanup_vm "$vm"
    done

    # Generate junit.xml even if tests failed (for CI artifact collection)
    if [[ -n "${TEST_RESULTS_PATH:-}" && -d "${TEST_RESULTS_PATH}" ]]; then
        generate_junit_report "${TEST_RESULTS_PATH}"
        # Also copy to parent results directory for CI
        local parent_dir=$(dirname "${TEST_RESULTS_PATH}")
        if [[ -d "$parent_dir" && "$parent_dir" != "${TEST_RESULTS_PATH}" ]]; then
            cp "${TEST_RESULTS_PATH}/junit.xml" "${parent_dir}/junit.xml" 2>/dev/null || true
        fi
    fi

    exit $exit_code
}

# Generate JUnit XML report from test results
generate_junit_report() {
    local results_dir=$1
    local junit_file="${results_dir}/junit.xml"
    local passed=$(grep -c "\[PASS\]" "${results_dir}"/*.txt 2>/dev/null || echo "0")
    local failed=$(grep -c "\[FAIL\]" "${results_dir}"/*.txt 2>/dev/null || echo "0")
    local total=$((passed + failed))
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    cat > "$junit_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="Pimeleon Tests" tests="${total}" failures="${failed}" time="0" timestamp="${timestamp}">
  <testsuite name="pimeleon" tests="${total}" failures="${failed}" errors="0" skipped="0" time="0">
EOF

    # Parse test results and add test cases
    for result_file in "${results_dir}"/*.txt; do
        if [[ -f "$result_file" ]]; then
            local suite_name=$(basename "$result_file" .txt)
            while IFS= read -r line; do
                if [[ "$line" == *"[PASS]"* ]]; then
                    local test_name="${line#*\[PASS\] }"
                    test_name="${test_name% passed}"
                    echo "    <testcase name=\"${test_name}\" classname=\"${suite_name}\" time=\"0\"/>" >> "$junit_file"
                elif [[ "$line" == *"[FAIL]"* ]]; then
                    local test_name="${line#*\[FAIL\] }"
                    echo "    <testcase name=\"${test_name}\" classname=\"${suite_name}\" time=\"0\">" >> "$junit_file"
                    echo "      <failure message=\"Test failed\">${line}</failure>" >> "$junit_file"
                    echo "    </testcase>" >> "$junit_file"
                fi
            done < "$result_file"
        fi
    done

    echo "  </testsuite>" >> "$junit_file"
    echo "</testsuites>" >> "$junit_file"

    log_info "JUnit report generated: $junit_file"
}

# Set trap for cleanup
trap cleanup_on_exit EXIT

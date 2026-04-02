#!/usr/bin/env bats
# Unit tests for shared/scripts/common.sh

PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
COMMON_SH="${PROJECT_ROOT}/shared/scripts/common.sh"

setup() {
    # Source common.sh inside a clean environment; set -E from common.sh is
    # contained to the subshell bats creates for each test.
    # shellcheck source=/dev/null
    source "$COMMON_SH"
}

# ---------------------------------------------------------------------------
# die
# ---------------------------------------------------------------------------

@test "die outputs an error message and exits with status 1" {
    run bash -c "source '${COMMON_SH}'; die 'something went wrong'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"something went wrong"* ]]
}

@test "die exit code is exactly 1" {
    run bash -c "source '${COMMON_SH}'; die 'fatal'"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# log functions
# ---------------------------------------------------------------------------

@test "log_info output contains [INFO]" {
    run log_info "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO]"* ]]
}

@test "log_info output contains the message text" {
    run log_info "hello world"
    [[ "$output" == *"hello world"* ]]
}

@test "log_warn output contains [WARN]" {
    run log_warn "test warning"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN]"* ]]
}

@test "log_warn output contains the message text" {
    run log_warn "disk nearly full"
    [[ "$output" == *"disk nearly full"* ]]
}

@test "log_error output contains [ERROR]" {
    run log_error "test error"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[ERROR]"* ]]
}

@test "log_error output contains the message text" {
    run log_error "build failed"
    [[ "$output" == *"build failed"* ]]
}

# ---------------------------------------------------------------------------
# has_apt_proxy
# ---------------------------------------------------------------------------

@test "has_apt_proxy returns 0 when APT_PROXY is non-empty" {
    APT_PROXY="192.168.1.1:3142"
    run has_apt_proxy
    [ "$status" -eq 0 ]
}

@test "has_apt_proxy returns 1 when APT_PROXY is empty string" {
    APT_PROXY=""
    run has_apt_proxy
    [ "$status" -eq 1 ]
}

@test "has_apt_proxy returns 1 when APT_PROXY is unset" {
    unset APT_PROXY
    run has_apt_proxy
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# get_qemu_binary
# ---------------------------------------------------------------------------

@test "get_qemu_binary returns qemu-arm-static for armhf" {
    RPI_ARCH="armhf"
    run get_qemu_binary
    [ "$status" -eq 0 ]
    [ "$output" = "qemu-arm-static" ]
}

@test "get_qemu_binary returns qemu-arm-static for arm (alias)" {
    RPI_ARCH="arm"
    run get_qemu_binary
    [ "$status" -eq 0 ]
    [ "$output" = "qemu-arm-static" ]
}

@test "get_qemu_binary returns qemu-aarch64-static for arm64" {
    RPI_ARCH="arm64"
    run get_qemu_binary
    [ "$status" -eq 0 ]
    [ "$output" = "qemu-aarch64-static" ]
}

@test "get_qemu_binary returns qemu-aarch64-static for aarch64 (alias)" {
    RPI_ARCH="aarch64"
    run get_qemu_binary
    [ "$status" -eq 0 ]
    [ "$output" = "qemu-aarch64-static" ]
}

@test "get_qemu_binary exits non-zero for unsupported architecture" {
    run bash -c "source '${COMMON_SH}'; RPI_ARCH=mips get_qemu_binary"
    [ "$status" -ne 0 ]
}

@test "get_qemu_binary error message mentions the unsupported arch" {
    run bash -c "source '${COMMON_SH}'; RPI_ARCH=mips get_qemu_binary"
    [[ "$output" == *"mips"* ]]
}

# ---------------------------------------------------------------------------
# safe_rm
# ---------------------------------------------------------------------------

@test "safe_rm exits non-zero when given a path outside sanctioned directories" {
    run bash -c "source '${COMMON_SH}'; safe_rm /etc/passwd"
    [ "$status" -ne 0 ]
}

@test "safe_rm output contains CRITICAL for out-of-bounds path" {
    run bash -c "source '${COMMON_SH}'; safe_rm /etc/passwd"
    [[ "$output" == *"CRITICAL"* ]]
}

@test "safe_rm does not delete when path is outside /tmp/build and /output" {
    run bash -c "source '${COMMON_SH}'; safe_rm /home/pi/important_file"
    [ "$status" -ne 0 ]
    [[ "$output" == *"CRITICAL"* ]]
}

@test "safe_rm prints a warning and returns 0 when no paths are provided" {
    run safe_rm
    [ "$status" -eq 0 ]
    [[ "$output" == *"no paths provided"* ]]
}

# ---------------------------------------------------------------------------
# is_service_enabled
# ---------------------------------------------------------------------------

@test "is_service_enabled returns 0 for hostapd with production profile" {
    ANSIBLE_DIR="${PROJECT_ROOT}/shared/ansible"
    PIMELEON_PROFILE="production"
    run is_service_enabled "hostapd"
    [ "$status" -eq 0 ]
}

@test "is_service_enabled returns 1 for wpa_supplicant with production profile (false in YAML)" {
    ANSIBLE_DIR="${PROJECT_ROOT}/shared/ansible"
    PIMELEON_PROFILE="production"
    run is_service_enabled "wpa_supplicant"
    [ "$status" -eq 1 ]
}

@test "is_service_enabled falls back to the production profile when unset" {
    run bash -c "source '${COMMON_SH}'; ANSIBLE_DIR='${PROJECT_ROOT}/shared/ansible'; unset PIMELEON_PROFILE; is_service_enabled hostapd"
    [ "$status" -eq 0 ]
}

@test "is_service_enabled exits non-zero when profile file does not exist" {
    ANSIBLE_DIR="${PROJECT_ROOT}/shared/ansible"
    PIMELEON_PROFILE="nonexistent_profile"
    run bash -c "source '${COMMON_SH}'; ANSIBLE_DIR='${PROJECT_ROOT}/shared/ansible'; PIMELEON_PROFILE='nonexistent_profile'; is_service_enabled hostapd"
    [ "$status" -ne 0 ]
}

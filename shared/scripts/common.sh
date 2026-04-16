#!/bin/bash
# Common functions for Pimeleon build scripts
set -E

# Project name for cache keys and output naming
PIMELEON_PROJECT_NAME="${PIMELEON_PROJECT_NAME:-pimeleon}"

# Ownership configuration
# Use BUILDER_UID if provided (e.g. from GitHub Actions build-arg), otherwise fallback to current user
PIMELEON_USER="${PIMELEON_USER:-${BUILDER_UID:-$(id -u)}}"
PIMELEON_GROUP="${PIMELEON_GROUP:-999}"

# Directory configuration
CACHE_DIR="${CACHE_DIR:-/cache}"

# Source logging library
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib-logging.sh"

# Project name for cache keys and output naming
die() {
    log_error "$*"
    exit 1
}

# Global cleanup tracking
CLEANUP_MOUNT_POINT="${CLEANUP_MOUNT_POINT:-}"
CLEANUP_LOOP_DEVICE="${CLEANUP_LOOP_DEVICE:-}"
CLEANUP_CHROOT_ACTIVE="${CLEANUP_CHROOT_ACTIVE:-false}"
CLEANUP_IMAGE_PATH="${CLEANUP_IMAGE_PATH:-}"
declare -a MOUNT_STACK=()

# Safe remove helper - prevents accidental deletion outside build directory
safe_rm() {
    local work_dir_base="/tmp/build"
    local output_dir_base="/output"

    if [[ $# -eq 0 ]]; then
        log_warn "safe_rm: no paths provided, ignoring"
        return
    fi

    for path in "$@"; do
        if [[ -z "$path" ]]; then
            continue
        fi

        # Only allow deletion within sanctioned directories
        if [[ "$path" == "${work_dir_base}"* ]] || \
            [[ -n "${WORK_DIR:-}" && "$path" == "${WORK_DIR}"* ]] || \
            [[ "$path" == "${output_dir_base}"* ]] || \
            [[ -n "${OUTPUT_DIR:-}" && "$path" == "${OUTPUT_DIR}"* ]]; then

            # Proactively find and unmount any sub-mounts under this path
            # Only if path is a directory
            if [[ -d "$path" ]]; then
                local nested_mounts
                nested_mounts=$(findmnt -n -o TARGET -R "$path" 2>/dev/null | sort -r || true)
                if [[ -n "$nested_mounts" ]]; then
                    log_warn "safe_rm: Found active mounts under $path, unmounting..."
                    for mnt in $nested_mounts; do
                        sudo umount "$mnt" 2>/dev/null || sudo umount -l "$mnt" 2>/dev/null || log_warn "safe_rm: Failed to unmount $mnt — loop device may remain attached"
                    done
                fi
            fi

            # We allow glob expansion here by not quoting $path in the final command
            # shellcheck disable=SC2086
            sudo rm -rf $path
        else
            die "CRITICAL: Attempted to delete path outside sanctioned directories: $path"
        fi
    done
}
# Cleanup function for trap handlers
cleanup_on_exit() {
    local exit_code=$?
    # Clear traps to prevent recursive calls during cleanup
    trap - EXIT ERR INT TERM
    set +e # Don't exit on error during cleanup

    # On failure (non-zero exit code)
    if [[ $exit_code -ne 0 ]]; then
        if [[ $exit_code -eq 130 ]]; then
            log_warn "Build interrupted by user (Ctrl+C). Cleaning up..."
        elif [[ $exit_code -eq 143 ]]; then
            log_warn "Build terminated by signal (SIGTERM). Cleaning up..."
        else
            log_error "Failure detected (exit code: $exit_code). Cleaning up..."
        fi
    fi

    # Only cleanup if we have something to clean
    if [[ -n "$CLEANUP_MOUNT_POINT" ]] || [[ -n "$CLEANUP_LOOP_DEVICE" ]] || [[ ${#MOUNT_STACK[@]} -gt 0 ]]; then
        # Cleanup chroot first if active
        if [[ "$CLEANUP_CHROOT_ACTIVE" == "true" ]]; then
            log_info "Cleaning up chroot before exit..."
            cleanup_chroot "$CLEANUP_MOUNT_POINT" || true
        fi

        # Unmount image
        if [[ -n "$CLEANUP_MOUNT_POINT" ]] || [[ -n "$CLEANUP_LOOP_DEVICE" ]]; then
            log_info "Unmounting image and detaching loop device..."
            unmount_image "$CLEANUP_MOUNT_POINT" "$CLEANUP_LOOP_DEVICE" || true
        fi

        # Extra safety: if we have a loop device, ensure it's detached even if unmount_image failed
        if [[ -n "$CLEANUP_LOOP_DEVICE" ]] && [[ -e "$CLEANUP_LOOP_DEVICE" ]]; then
            log_warn "Ensuring loop device $CLEANUP_LOOP_DEVICE is detached..."
            sudo kpartx -d "$CLEANUP_LOOP_DEVICE" 2>/dev/null || true
            sudo losetup -d "$CLEANUP_LOOP_DEVICE" 2>/dev/null || true
        fi
    fi

    if [[ $exit_code -ne 0 ]]; then
        if [[ -n "${LOG_FILE:-}" ]]; then
            log_info "Detailed build log: ${LOG_FILE}"
        fi
        if [[ -n "${CLEANUP_IMAGE_PATH:-}" ]]; then
            if [[ -f "$CLEANUP_IMAGE_PATH" ]]; then
                log_warn "Removing partial image: $CLEANUP_IMAGE_PATH"
                sudo rm -f "$CLEANUP_IMAGE_PATH" || true
                sudo rm -f "${CLEANUP_IMAGE_PATH}.xz" || true
                sudo rm -f "${CLEANUP_IMAGE_PATH}.sha256" || true
            fi
        fi
    fi

    # Exit with original code
    exit $exit_code
}

# Check if a service is enabled in the current profile
is_service_enabled() {
    local service_name=$1
    local ansible_dir="${ANSIBLE_DIR:-/ansible}"
    local profile_path="${ansible_dir}/vars/common/profiles/${PIMELEON_PROFILE:-production}.yml"

    if [[ ! -f "$profile_path" ]]; then
        die "FATAL: Profile file not found: $profile_path"
    fi

    # Use Python for robust YAML parsing (available in builder image)
    if python3 -c "import yaml; import os; profile = yaml.safe_load(open('$profile_path')) if os.path.exists('$profile_path') else {}; exit(0 if profile.get('services_enabled', {}).get('$service_name') == True else 1)" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Check if APT proxy is configured (set APT_PROXY=host:port to enable)
has_apt_proxy() {
    [[ -n "${APT_PROXY:-}" ]]
}

# Cleanup stale mounts from previous failed builds
cleanup_stale_mounts() {
    log_info "Checking for stale mounts from previous builds..."
    local work_dir_base="/tmp/build"

    # Find and unmount any work-dir related mounts (in reverse order for nested mounts)
    # Use || true to prevent script exit if no mounts are found
    local stale_mounts
    stale_mounts=$(mount | grep "${work_dir_base}" | awk '{print $3}' | sort -r || true)
    if [[ -n "$stale_mounts" ]]; then
        for mnt in $stale_mounts; do
            log_warn "Unmounting stale mount: $mnt"
            sudo umount -l "$mnt" 2>/dev/null || log_warn "Failed to unmount stale mount: $mnt — subsequent build may fail"
        done
    fi

    # Find and detach any leftover loop devices with pimeleon images
    # Check for both the image name and the mount point path
    local stale_loops
    stale_loops=$(losetup -l -n -O NAME,BACK-FILE 2>/dev/null | grep -E "pimeleon|${work_dir_base}" | awk '{print $1}' || true)
    if [[ -n "$stale_loops" ]]; then
        for loop in $stale_loops; do
            log_warn "Detaching stale loop device: $loop"
            sudo kpartx -d "$loop" 2>/dev/null || log_warn "Failed to remove partition mappings for $loop"
            sudo losetup -d "$loop" 2>/dev/null || log_warn "Failed to detach loop device $loop — device may remain attached"
        done
    fi
}
# Check if running as root or with sudo
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root or with sudo"
    fi
}

# Get the QEMU static binary name for the target architecture
get_qemu_binary() {
    case "${RPI_ARCH:-armhf}" in
        arm64|aarch64) echo "qemu-aarch64-static" ;;
        armhf|arm)     echo "qemu-arm-static" ;;
        *)             die "Unsupported architecture: ${RPI_ARCH}" ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    local qemu_binary
    qemu_binary=$(get_qemu_binary)

    local required_commands=(
        "debootstrap"
        "${qemu_binary}"
        "parted"
        "kpartx"
        "mkfs.vfat"
        "mkfs.ext4"
        "ansible-playbook"
    )

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            die "Required command not found: $cmd"
        fi
    done

    # Check for qemu-user-static
    if [[ ! -f "/usr/bin/${qemu_binary}" ]]; then
        die "${qemu_binary} not found. Please install qemu-user-static package."
    fi

    # Check binfmt support
    if [[ ! -d /proc/sys/fs/binfmt_misc ]]; then
        die "binfmt_misc not mounted. Please enable binfmt support."
    fi
}

# Mount image partitions
mount_image() {
    local image_path=$1
    local mount_point=$2

    log_info "Mounting image: $image_path"

    # Create loop device
    local loop_device
    loop_device=$(sudo losetup -f --show "$image_path")

    # Register for cleanup as soon as loop device is created
    CLEANUP_LOOP_DEVICE="$loop_device"

    # Scan for partitions
    sudo kpartx -av "$loop_device"
    sleep 2

    # Get partition devices
    local loop_name
    loop_name=$(basename "$loop_device")
    local boot_part="/dev/mapper/${loop_name}p1"
    local root_part="/dev/mapper/${loop_name}p2"

    # Mount partitions (Track in stack for reverse cleanup)
    sudo mkdir -p "$mount_point"
    sudo mount "$root_part" "$mount_point"
    MOUNT_STACK+=("$mount_point")

    sudo mkdir -p "$mount_point/boot"
    sudo mount "$boot_part" "$mount_point/boot"
    MOUNT_STACK+=("$mount_point/boot")

    # Register for cleanup on error
    CLEANUP_MOUNT_POINT="$mount_point"
    CLEANUP_LOOP_DEVICE="$loop_device"

    echo "$loop_device"
}

# Unmount image partitions
unmount_image() {
    local mount_point=$1
    local loop_device=$2

    log_info "Unmounting image stack..."

    # Check for any sub-mounts not in our stack (e.g. from failed manual checks)
    if [[ -d "$mount_point" ]]; then
        local extra_mounts
        extra_mounts=$(findmnt -n -o TARGET -R "$mount_point" | sort -r | grep -v "^${mount_point}$" || true)
        if [[ -n "$extra_mounts" ]]; then
            log_warn "Found extra mounts under $mount_point, cleaning up..."
            for mnt in $extra_mounts; do
                sudo umount "$mnt" 2>/dev/null || sudo umount -l "$mnt" 2>/dev/null || true
            done
        fi
    fi

    # Unmount everything in reverse order from the stack
    for ((i=${#MOUNT_STACK[@]}-1; i>=0; i--)); do
        local mnt="${MOUNT_STACK[$i]}"
        if mountpoint -q "$mnt" 2>/dev/null; then
            # Try standard umount first, then lazy
            sudo umount "$mnt" 2>/dev/null || sudo umount -l "$mnt" || log_warn "Failed to unmount $mnt"
        fi
    done
    MOUNT_STACK=()

    # Remove partition mappings
    if [[ -n "$loop_device" ]]; then
        # Ensure kpartx removes mappings
        sudo kpartx -d "$loop_device" 2>/dev/null || true
        sudo losetup -d "$loop_device" 2>/dev/null || true
    fi

    # Clear cleanup tracking
    CLEANUP_MOUNT_POINT=""
    CLEANUP_LOOP_DEVICE=""
}

# Setup chroot environment
setup_chroot() {
    local chroot_dir=$1

    log_info "Setting up chroot environment"

    # Copy qemu static binary for target architecture
    local qemu_binary
    qemu_binary=$(get_qemu_binary)
    sudo cp "/usr/bin/${qemu_binary}" "$chroot_dir/usr/bin/"

    # Mount special filesystems
    sudo mount -t proc proc "$chroot_dir/proc"
    sudo mount -t sysfs sys "$chroot_dir/sys"
    sudo mount -t devtmpfs dev "$chroot_dir/dev"
    sudo mount -t devpts devpts "$chroot_dir/dev/pts"

    # Write resolv.conf with real DNS servers (Docker's 127.0.0.11 doesn't work in chroot)
    # Ensure it's a regular file, not a symlink
    sudo rm -f "$chroot_dir/etc/resolv.conf"
    sudo tee "$chroot_dir/etc/resolv.conf" > /dev/null <<EOF
# DNS for chroot build environment
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

    # Copy host file to prevent 'unable to resolve host' warnings
    sudo cp /etc/hosts "$chroot_dir/etc/hosts"
    # Copy nsswitch.conf to ensure getent works correctly in chroot
    sudo cp /etc/nsswitch.conf "$chroot_dir/etc/nsswitch.conf"

    # Pre-populate /etc/hosts with GitHub IPs to bypass DNS resolution checks during build
    # These match current global IPs for github.com and raw.githubusercontent.com
    sudo tee -a "$chroot_dir/etc/hosts" > /dev/null <<EOF
140.82.121.3 github.com
140.82.121.4 github.com
185.199.108.133 raw.githubusercontent.com
185.199.109.133 raw.githubusercontent.com
185.199.110.133 raw.githubusercontent.com
185.199.111.133 raw.githubusercontent.com
EOF

    # Prevent services from starting in chroot
    sudo tee "$chroot_dir/usr/sbin/policy-rc.d" > /dev/null <<EOF
#!/bin/sh
exit 101
EOF
    sudo chmod +x "$chroot_dir/usr/sbin/policy-rc.d"

    # Track chroot state for cleanup
    CLEANUP_CHROOT_ACTIVE=true
}

# Cleanup chroot environment
cleanup_chroot() {
    local chroot_dir=$1

    log_info "Cleaning up chroot environment"

    # Remove policy-rc.d
    sudo rm -f "$chroot_dir/usr/sbin/policy-rc.d"

    # Unmount special filesystems (reverse order)
    sudo umount "$chroot_dir/dev/pts" 2>/dev/null || true
    sudo umount "$chroot_dir/dev" 2>/dev/null || true
    sudo umount "$chroot_dir/sys" 2>/dev/null || true
    sudo umount "$chroot_dir/proc" 2>/dev/null || true

    # Remove qemu static binary
    local qemu_binary
    qemu_binary=$(get_qemu_binary)
    sudo rm -f "$chroot_dir/usr/bin/${qemu_binary}"

    # Clear chroot tracking
    CLEANUP_CHROOT_ACTIVE=false
}

# Validate build environment and variables
validate_build_environment() {
    log_info "Validating build environment..."

    local required_vars=(
        "TARGET_PLATFORM"
        "PIMELEON_RPI_MODEL"
        "RPI_ARCH"
        "RASPBIAN_VERSION"
        "OUTPUT_DIR"
        "CACHE_DIR"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            die "Required environment variable not set: $var"
        fi
    done

    # Check for minimum disk space (5GB recommended for build)
    local free_space
    free_space=$(df -m /tmp | tail -1 | awk '{print $4}')
    if [[ "$free_space" -lt 5000 ]]; then
        log_warn "Low disk space on /tmp ($free_space MB). Build might fail."
    fi

    # Verify network connectivity (Prioritize Cache Server, then Internet)
    local reachable=false
    if has_apt_proxy; then
        local apt_host="${APT_PROXY%:*}"
        local apt_port="${APT_PROXY##*:}"
        # Try to connect to the APT Cache port (TCP)
        if timeout 1 bash -c "cat < /dev/null > /dev/tcp/${apt_host}/${apt_port}" 2>/dev/null; then
            log_info "APT proxy (${APT_PROXY}) is reachable."
            reachable=true
        fi
    fi

    if [[ "$reachable" == "false" ]]; then
        # Fallback to checking DNS or HTTP port instead of ICMP ping
        if timeout 1 bash -c "cat < /dev/null > /dev/tcp/8.8.8.8/53" 2>/dev/null || \
            timeout 1 bash -c "cat < /dev/null > /dev/tcp/google.com/80" 2>/dev/null; then
            log_info "Internet connectivity detected."
            reachable=true
        else
            if has_apt_proxy; then
                log_warn "Neither APT proxy (${APT_PROXY}) nor Internet are reachable. Build might fail."
            else
                log_warn "No internet connectivity detected. Package installation might fail."
            fi
        fi
    fi
}

# Verify stage completion by checking for critical artifacts
verify_stage() {
    local stage=$1
    local mount_point=$2
    log_info "Verifying Stage $stage..."

    case "$stage" in
        1)
            [[ -f "${mount_point}/etc/fstab" ]] || die "Stage 1 verification failed: /etc/fstab missing"
            [[ -f "${mount_point}/boot/config.txt" ]] || die "Stage 1 verification failed: /boot/config.txt missing"
            ;;
        2)
            [[ -f "${mount_point}/etc/shadow" ]] || die "Stage 2 verification failed: Base system compromised"
            [[ -x "${mount_point}/usr/bin/python3" ]] || die "Stage 2 verification failed: python3 missing"
            # Check for at least one critical service file
            [[ -f "${mount_point}/lib/systemd/system/ssh.service" ]] || [[ -f "${mount_point}/usr/lib/systemd/system/ssh.service" ]] || die "Stage 2 verification failed: ssh.service missing"
            ;;
        3)
            # Verify cleanup was successful
            [[ ! -d "${mount_point}/var/lib/apt/lists/partial" ]] || log_warn "Stage 3 warning: APT partial lists still exist"
            ;;
    esac
    log_info "Stage $stage verified successfully."
}

# Configure APT cache for chroot environment
configure_chroot_apt_proxy() {
    local mount_point=$1

    # Increase APT cache limits and disable translations to prevent "Cannot allocate memory" errors
    # especially during ARM emulation (QEMU user-mode)
    sudo mkdir -p "${mount_point}/etc/apt/apt.conf.d"
    sudo tee "${mount_point}/etc/apt/apt.conf.d/99build-tuning" > /dev/null <<EOF
# Build-time APT Tuning
APT::Cache-Start "256000000";
Acquire::Languages "none";
EOF

    if has_apt_proxy; then
        log_info "Configuring APT cache for chroot: ${APT_PROXY}"
        sudo tee "${mount_point}/etc/apt/apt.conf.d/01proxy" > /dev/null <<EOF
# APT Cache Configuration for Build Process
Acquire::http::Proxy "http://${APT_PROXY}";
# Longer timeouts for slow cache/upstream responses
Acquire::http::Timeout "120";
Acquire::https::Timeout "120";
Acquire::Retries "3";
EOF
    fi

    # Clean up partial lists that might be corrupt and cause "Cannot allocate memory" on parse
    sudo rm -rf "${mount_point}/var/lib/apt/lists/partial/"*
}

# Remove APT cache proxy from chroot
remove_chroot_apt_proxy() {
    local mount_point=$1
    if [[ -f "${mount_point}/etc/apt/apt.conf.d/01proxy" ]]; then
        log_info "Removing APT cache configuration from chroot"
        sudo rm -f "${mount_point}/etc/apt/apt.conf.d/01proxy"
    fi
    if [[ -f "${mount_point}/etc/apt/apt.conf.d/99build-tuning" ]]; then
        sudo rm -f "${mount_point}/etc/apt/apt.conf.d/99build-tuning"
    fi
}

# Migrate legacy APT keyring to modern format (prevents deprecation warnings)
migrate_apt_keyring() {
    local mount_point=$1
    if [ -f "${mount_point}/etc/apt/trusted.gpg" ]; then
        log_info "Migrating legacy APT keyring to modern format"
        sudo mkdir -p "${mount_point}/etc/apt/trusted.gpg.d"
        sudo gpg --no-default-keyring \
            --keyring "${mount_point}/etc/apt/trusted.gpg" \
            --export 2>/dev/null | \
            sudo gpg --no-default-keyring \
            --keyring "gnupg-ring:${mount_point}/etc/apt/trusted.gpg.d/raspbian-archive-keyring.gpg" \
            --import 2>/dev/null || true
        sudo chmod 644 "${mount_point}/etc/apt/trusted.gpg.d/raspbian-archive-keyring.gpg" 2>/dev/null || true
        sudo rm -f "${mount_point}/etc/apt/trusted.gpg"
        log_info "Legacy keyring migrated and removed"
    fi
}

# Run command in chroot with proxy support
chroot_run() {
    local chroot_dir=$1
    shift

    # Construct proxy environment if available
    local -a proxy_args=()
    if has_apt_proxy; then
        local proxy_url="http://${APT_PROXY}"
        proxy_args=(
            "http_proxy=${proxy_url}"
            "https_proxy=${proxy_url}"
            "ftp_proxy=${proxy_url}"
            "no_proxy=localhost,127.0.0.1,local"
        )
    fi

    # Use env to pass the proxy variables into the chroot environment
    if [[ ${#proxy_args[@]} -gt 0 ]]; then
        sudo DEBIAN_FRONTEND=noninteractive chroot "$chroot_dir" env "${proxy_args[@]}" "$@"
    else
        sudo DEBIAN_FRONTEND=noninteractive chroot "$chroot_dir" "$@"
    fi
}

# Generate image metadata
generate_metadata() {
    local image_path=$1
    local metadata_file="${image_path}.metadata.json"

    log_info "Generating metadata: $metadata_file"

    # Calculate checksums
    local md5sum
    md5sum=$(md5sum "$image_path" | cut -d' ' -f1)
    local sha256sum
    sha256sum=$(sha256sum "$image_path" | cut -d' ' -f1)
    local size
    size=$(stat -c%s "$image_path")

    # Create metadata JSON
    cat > "$metadata_file" <<EOF
{
    "version": "$(date +%Y%m%d-%H%M%S)",
    "build_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "commit_sha": "${CI_COMMIT_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}",
    "image_name": "$(basename "$image_path")",
    "image_size": $size,
    "checksums": {
        "md5": "$md5sum",
        "sha256": "$sha256sum"
    },
    "build_info": {
        "rpi_model": "${PIMELEON_RPI_MODEL:-3B+}",
        "raspbian_version": "${RASPBIAN_VERSION:-buster}",
        "builder_version": "1.0.0",
        "commit_sha": "${CI_COMMIT_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}",
        "builder_image_ref": "${BUILDER_IMAGE_REF:-unknown}",
        "builder_image_digest": "${BUILDER_IMAGE_DIGEST:-unknown}"
    }
}
EOF
}

# =============================================================================
# App Configuration Functions (Monorepo)
# =============================================================================

# Parse app name to derive build configuration
# Format: {platform}-{debian_version}  e.g., rpi3-bookworm, rpi4-bookworm
load_app_config() {
    local app_name=$1

    if [[ -z "$app_name" ]]; then
        die "App name is required"
    fi

    # Parse app name: {device}-{debian}
    local device="${app_name%%-*}"      # rpi3, rpi4
    local debian="${app_name##*-}"      # bookworm

    # Derive configuration from device
    case "$device" in
        rpi3)
            export PIMELEON_RPI_MODEL="3B+"
            export RPI_ARCH="armhf"
            export PIMELEON_IMAGE_SIZE="${PIMELEON_IMAGE_SIZE:-3G}"
            ;;
        rpi4)
            export PIMELEON_RPI_MODEL="4B"
            export RPI_ARCH="arm64"
            export PIMELEON_IMAGE_SIZE="${PIMELEON_IMAGE_SIZE:-4G}"
            ;;
        *)
            log_error "App not found: $app_name (unknown device: $device)"
            list_apps
            die "Please specify a valid app name"
            ;;
    esac

    export RASPBIAN_VERSION="$debian"

    # Validate that the platform group directory exists in shared/ansible/inventory/group_vars/
    local group_name
    group_name="raspberrypi_$(echo "${PIMELEON_RPI_MODEL}" | tr '[:upper:]' '[:lower:]' | tr -d '+' | sed 's/3b/3bplus/')"
    if [[ ! -d "${ANSIBLE_DIR:-/ansible}/inventory/group_vars/${group_name}" ]]; then
        log_error "Platform group config not found for: ${app_name} (expected group: ${group_name})"
        list_apps
        die "Configuration missing for this platform"
    fi

    log_info "App: ${app_name}"
    log_info "  Model: ${PIMELEON_RPI_MODEL}, Arch: ${RPI_ARCH}, Debian: ${RASPBIAN_VERSION}"
}

# List available apps
list_apps() {
    local ansible_dir="${ANSIBLE_DIR:-/ansible}"
    local group_vars_dir="${ansible_dir}/inventory/group_vars"

    if [[ ! -d "$group_vars_dir" ]]; then
        die "FATAL: No Ansible group_vars directory found at: $group_vars_dir"
    fi

    echo ""
    echo "Available platforms:"
    echo "===================="
    for group_dir in "${group_vars_dir}"/raspberrypi_*/; do
        [[ -d "$group_dir" ]] || continue
        local group_name
        group_name=$(basename "$group_dir")
        local model_suffix="${group_name#raspberrypi_}"

        case "$model_suffix" in
            3bplus)
                printf "  %-20s (%s, %s)\n" "rpi3-bookworm" "3B+" "bookworm"
                ;;
            4b)
                printf "  %-20s (%s, %s)\n" "rpi4-bookworm" "4B" "bookworm"
                ;;
            *)
                printf "  %-20s (%s)\n" "$group_name" "custom"
                ;;
        esac
    done
    echo ""
}

# =============================================================================
# Cache management
# =============================================================================

get_cache_path() {
    local cache_key=$1
    echo "${CACHE_DIR}/${cache_key}"
}

cache_exists() {
    local cache_key=$1
    local cache_path
    cache_path=$(get_cache_path "$cache_key")
    [[ -f "$cache_path" ]]
}

cache_get() {
    local cache_key=$1
    local destination=$2
    local cache_path
    cache_path=$(get_cache_path "$cache_key")

    if cache_exists "$cache_key"; then
        log_info "Using cached file: $cache_key"
        sudo cp "$cache_path" "$destination"
        sudo chown "${PIMELEON_USER}:${PIMELEON_GROUP}" "$destination"
        return 0
    else
        return 1
    fi
}

cache_put() {
    local source=$1
    local cache_key=$2
    local cache_path
    cache_path=$(get_cache_path "$cache_key")

    log_info "Caching file: $cache_key"
    sudo mkdir -p "$(dirname "$cache_path")"
    sudo cp "$source" "$cache_path"
    sudo chown "${PIMELEON_USER}:${PIMELEON_GROUP}" "$cache_path"
}

# Fetch a pre-built binary package from the GitLab Generic Package Registry.
# Usage: fetch_pimeleon_apps <package> <arch> <download_dir>
# Saves as <download_dir>/<package>.tar.gz (matching existing Ansible task expectations).
# Returns 1 if PIMELEON_APPS_PROJECT_ID is not set or package cannot be fetched.
fetch_pimeleon_apps() {
    local package="$1"
    local arch="$2"
    local download_dir="$3"

    [[ -n "${PIMELEON_APPS_PROJECT_ID:-}" ]] || die "PIMELEON_APPS_PROJECT_ID is not set"
    [[ -n "${PIMELEON_APPS_READ_TOKEN:-}" ]]  || die "PIMELEON_APPS_READ_TOKEN is not set"

    local reg="https://gitlab.pirouter.dev/api/v4/projects/${PIMELEON_APPS_PROJECT_ID}/packages/generic"
    local list_url="https://gitlab.pirouter.dev/api/v4/projects/${PIMELEON_APPS_PROJECT_ID}/packages?package_type=generic&package_name=${package}&per_page=5&order_by=created_at&sort=desc"

    log_info "Listing ${package}/${arch} versions in pi-router-apps registry"
    local raw http_code api_response
    raw=$(curl -sLk \
            -H "PRIVATE-TOKEN: ${PIMELEON_APPS_READ_TOKEN}" \
            -w "\n%{http_code}" \
        "${list_url}")
    http_code=$(echo "${raw}" | tail -1)
    api_response=$(echo "${raw}" | head -n -1)

    if [[ "${http_code}" != "200" ]]; then
        log_error "Registry API request failed for ${package}: HTTP ${http_code}"
        log_error "URL: ${list_url}"
        log_error "Response: ${api_response}"
        return 1
    fi

    local version
    version=$(echo "${api_response}" \
            | python3 -c "import json,sys; d=json.load(sys.stdin); v=next((p.get('version','') for p in d if p.get('version','').startswith('${arch}-')),''); print(v.replace('${arch}-','',1)) if v else None" \
        2>/dev/null || true)

    if [[ -z "${version}" ]]; then
        log_warn "No published version found for ${package}/${arch} in apps registry"
        return 1
    fi

    local fname="${package}-${version}-${arch}-pimeleon.tar.gz"
    local url="${reg}/${package}/${arch}-${version}/${fname}"
    log_info "Resolved ${package} ${version} (${arch}) in pi-router-apps registry"
    log_info "Download URL: ${url}"

    http_code=$(sudo curl -sLk \
            -H "PRIVATE-TOKEN: ${PIMELEON_APPS_READ_TOKEN}" \
            -o "${download_dir}/${package}.tar.gz" \
            -w "%{http_code}" \
        "${url}")
    if [[ "${http_code}" != "200" ]] || [[ ! -s "${download_dir}/${package}.tar.gz" ]]; then
        log_error "Failed to fetch ${package}: HTTP ${http_code} (or empty file)"
        log_error "URL: ${url}"
        sudo rm -f "${download_dir}/${package}.tar.gz"
        return 1
    fi

    log_info "Fetched ${package} ${version} -> ${download_dir}/${package}.tar.gz"
    return 0
}

# Fetch a pre-built binary package from GitHub Releases (pimeleon/pimeleon-apps).
# Usage: fetch_pimeleon_apps_github <package> <arch> <download_dir>
# Saves as <download_dir>/<package>.tar.gz.
# Requires: PIMELEON_APPS_GITHUB_TOKEN (CI/CD variable).
fetch_pimeleon_apps_github() {
    local package="$1"
    local arch="$2"
    local download_dir="$3"

    [[ -n "${PIMELEON_APPS_GITHUB_TOKEN:-}" ]] || die "PIMELEON_APPS_GITHUB_TOKEN is not set"

    local auth_args=(-H "Authorization: Bearer ${PIMELEON_APPS_GITHUB_TOKEN}")
    local api_url="https://api.github.com/repos/pimeleon/pimeleon-apps/releases"

    local gh_list_url="${api_url}?per_page=10"
    local raw http_code api_response
    log_info "Listing GitHub releases for ${package}/${arch}"
    raw=$(curl -sL \
            "${auth_args[@]}" \
            -H "Accept: application/vnd.github+json" \
            -w "\n%{http_code}" \
        "${gh_list_url}")
    http_code=$(echo "${raw}" | tail -1)
    api_response=$(echo "${raw}" | head -n -1)

    if [[ "${http_code}" != "200" ]]; then
        log_error "GitHub API request failed for ${package}: HTTP ${http_code}"
        log_error "URL: ${gh_list_url}"
        log_error "Response: ${api_response}"
        return 1
    fi

    # Find the most recent asset matching <package>-*-<arch>-*.tar.gz
    local asset_url
    asset_url=$(echo "${api_response}" \
            | python3 -c "import json,sys;data=json.load(sys.stdin);url=next((a['browser_download_url'] for r in data for a in r.get('assets',[]) if a.get('name','').startswith('${package}-') and '-${arch}-' in a.get('name','') and a.get('name','').endswith('.tar.gz')),None);print(url) if url else None" \
        2>/dev/null || true)

    if [[ -z "${asset_url}" ]]; then
        log_warn "No GitHub release asset found for ${package}/${arch} in pimeleon/pimeleon-apps"
        return 1
    fi

    log_info "Resolved ${package} (${arch}) in GitHub releases"
    log_info "Download URL: ${asset_url}"
    http_code=$(sudo curl -sL \
            "${auth_args[@]}" \
            -o "${download_dir}/${package}.tar.gz" \
            -w "%{http_code}" \
        "${asset_url}")
    if [[ "${http_code}" != "200" ]] || [[ ! -s "${download_dir}/${package}.tar.gz" ]]; then
        log_error "Failed to download ${package} from GitHub: HTTP ${http_code} (or empty file)"
        log_error "URL: ${asset_url}"
        sudo rm -f "${download_dir}/${package}.tar.gz"
        return 1
    fi

    log_info "Fetched ${package} from GitHub -> ${download_dir}/${package}.tar.gz"
    return 0
}

# Get a pre-built binary package from the appropriate source based on build context.
# CI production builds (tag or push/MR to release/*): GHCR image (pre-populated via PIMELEON_APPS_LOCAL_PATH).
# CI development builds (push/MR to develop): GitLab package registry.
# Other non-release CI branches also use GitLab registry as the safest default.
# Local builds: local mounted registry-apps path, then GitLab registry as fallback.
# Source can be forced via PIMELEON_APPS_SOURCE=gitlab|github.
# For github source: artifacts must be pre-extracted from ghcr.io/pimeleon/pimeleon-apps/builder-armhf:latest
# into PIMELEON_APPS_LOCAL_PATH (default: /workspace/registry-apps) before the builder container starts.
# Usage: get_pimeleon_apps_artifact <package> <arch> <download_dir>
get_pimeleon_apps_artifact() {
    local package="$1"
    local arch="$2"
    local download_dir="$3"
    local local_path="${PIMELEON_APPS_LOCAL_PATH:-/workspace/registry-apps}"

    # 1. CI environment: auto-detect source unless explicitly set
    if [[ -n "${CI:-}" ]] || [[ -n "${GITLAB_CI:-}" ]]; then
        local source="${PIMELEON_APPS_SOURCE:-}"
        if [[ -z "${source}" ]]; then
            if [[ "${CI_COMMIT_BRANCH:-}" =~ ^release/ ]] || \
               [[ "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}" =~ ^release/ ]]; then
                source="github"
                log_info "Auto-detected apps source: github (production build)"
            elif [[ "${CI_COMMIT_BRANCH:-}" == "develop" ]] || \
                 [[ "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}" == "develop" ]]; then
                source="gitlab"
                log_info "Auto-detected apps source: gitlab (develop build)"
            else
                source="gitlab"
                log_info "Auto-detected apps source: gitlab (non-release CI build)"
            fi
        fi
        case "${source}" in
            github)
                log_info "CI (production): fetching ${package} from GHCR pre-populated path"
                local github_path="${PIMELEON_APPS_LOCAL_PATH:-/workspace/registry-apps}"
                local github_file
                github_file=$(find "${github_path}" -maxdepth 2 \
                    -name "${package}-*-${arch}-*.tar.gz" 2>/dev/null | head -1)
                if [[ -n "${github_file:-}" ]]; then
                    log_info "Using GHCR artifact: ${github_file}"
                    sudo cp "${github_file}" "${download_dir}/${package}.tar.gz"
                    sudo chown "${PIMELEON_USER}:${PIMELEON_GROUP}" \
                        "${download_dir}/${package}.tar.gz"
                    return 0
                fi
                # Fallback: GHCR path not pre-populated — download from GitHub releases
                log_info "GHCR path empty, falling back to GitHub releases"
                fetch_pimeleon_apps_github "$package" "$arch" "$download_dir"
                return $?
                ;;
            gitlab)
                log_info "CI (development): fetching ${package} from GitLab registry"
                fetch_pimeleon_apps "$package" "$arch" "$download_dir"
                return $?
                ;;
            *)
                die "Unknown PIMELEON_APPS_SOURCE '${source}' — must be 'gitlab' or 'github'"
                ;;
        esac
    fi

    # 2. Local environment: Prioritize local cache if directory exists
    if [[ -d "${local_path}" ]]; then
        log_info "Checking local apps cache for ${package} in ${local_path}"

        # New pi-router-apps structure (flat in output/):
        # {package}-{version}-{arch}-pimeleon.tar.gz
        # The script currently expects {package}.tar.gz in the download_dir.

        local local_file
        # Look for the artifact in the sibling output directory if it matches the naming pattern
        # The naming pattern from pi-router-apps/output is {package}-*-{arch}-pimeleon.tar.gz
        local_file=$(find "${local_path}" -maxdepth 2 -name "${package}-*-${arch}-*.tar.gz" | head -1)

        if [[ -n "${local_file:-}" ]]; then
            log_info "Using local artifact: ${local_file}"
            log_info "Copying ${package} artifact into ${download_dir}"
            sudo cp "${local_file}" "${download_dir}/${package}.tar.gz"
            sudo chown "${PIMELEON_USER}:${PIMELEON_GROUP}" "${download_dir}/${package}.tar.gz"
            return 0
        fi

        # Fallback to existing structure checks for compatibility
        if [[ -f "${local_path}/${package}/output/${arch}/${package}.tar.gz" ]]; then
            local_file="${local_path}/${package}/output/${arch}/${package}.tar.gz"
        elif [[ -f "${local_path}/${package}/${arch}/${package}.tar.gz" ]]; then
            local_file="${local_path}/${package}/${arch}/${package}.tar.gz"
        elif [[ -f "${local_path}/${package}/${package}.tar.gz" ]]; then
            local_file="${local_path}/${package}/${package}.tar.gz"
        fi

        if [[ -n "${local_file:-}" ]]; then
            log_info "Using local artifact: ${local_file}"
            log_info "Copying ${package} artifact into ${download_dir}"
            sudo cp "${local_file}" "${download_dir}/${package}.tar.gz"
            sudo chown "${PIMELEON_USER}:${PIMELEON_GROUP}" "${download_dir}/${package}.tar.gz"
            return 0
        fi
        log_warn "Artifact for ${package} (${arch}) not found in local path ${local_path}"
    fi

    # 3. Local fallback: try GitLab registry if credentials are available
    if [[ -n "${PIMELEON_APPS_PROJECT_ID:-}" ]] && [[ -n "${PIMELEON_APPS_READ_TOKEN:-}" ]]; then
        log_info "Falling back to GitLab registry for ${package}"
        if fetch_pimeleon_apps "$package" "$arch" "$download_dir"; then
            return 0
        fi
    fi

    return 1
}

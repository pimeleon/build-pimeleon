#!/bin/bash
# Common functions for Pimeleon build scripts

# Project name for cache keys and output naming
PIMELEON_PROJECT_NAME="${PIMELEON_PROJECT_NAME:-pimeleon}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Error handling
die() {
    log_error "$*"
    exit 1
}

# Global cleanup tracking
CLEANUP_MOUNT_POINT=""
CLEANUP_LOOP_DEVICE=""
CLEANUP_CHROOT_ACTIVE=false
CLEANUP_IMAGE_PATH=""

# Cleanup function for trap handlers
cleanup_on_exit() {
    local exit_code=$?

    # Only cleanup if we have something to clean
    if [[ -n "$CLEANUP_MOUNT_POINT" ]] || [[ -n "$CLEANUP_LOOP_DEVICE" ]]; then
        log_warn "Cleanup triggered (exit code: $exit_code)"

        # Cleanup chroot first if active
        if [[ "$CLEANUP_CHROOT_ACTIVE" == "true" ]]; then
            cleanup_chroot "$CLEANUP_MOUNT_POINT" || true
        fi

        # Unmount image
        if [[ -n "$CLEANUP_MOUNT_POINT" ]] && [[ -n "$CLEANUP_LOOP_DEVICE" ]]; then
            unmount_image "$CLEANUP_MOUNT_POINT" "$CLEANUP_LOOP_DEVICE" || true
        fi
    fi

    # On failure, remove partial/corrupted image file
    if [[ $exit_code -ne 0 ]] && [[ -n "$CLEANUP_IMAGE_PATH" ]] && [[ -f "$CLEANUP_IMAGE_PATH" ]]; then
        log_warn "Build failed - removing partial image: $CLEANUP_IMAGE_PATH"
        rm -f "$CLEANUP_IMAGE_PATH" || true
        rm -f "${CLEANUP_IMAGE_PATH}.xz" || true
        rm -f "${CLEANUP_IMAGE_PATH}.sha256" || true
    fi

    # Re-exit with original code
    exit $exit_code
}

# Check if a service is enabled in the current profile
is_service_enabled() {
    local service_name=$1
    local ansible_dir="${WORKSPACE_DIR:-/workspace}/shared/ansible"
    local profile_path="${ansible_dir}/inventory/group_vars/all/profiles/${PIMELEON_PROFILE:-development}.yml"

    if [[ ! -f "$profile_path" ]]; then
        log_warn "Profile file not found: $profile_path"
        # Default to false if profile doesn't exist to avoid unwanted failures
        return 1
    fi

    # Simple parser for "service_name: true" under "services_enabled:"
    if grep -A 50 "services_enabled:" "$profile_path" 2>/dev/null | grep -q "^\s*${service_name}:\s*true"; then
        return 0 # Service is enabled
    else
        return 1 # Service is not enabled or not found
    fi
}

# Cleanup stale mounts from previous failed builds
cleanup_stale_mounts() {
    log_info "Checking for stale mounts from previous builds..."

    # Find and unmount any pimeleon-related mounts (in reverse order for nested mounts)
    local stale_mounts=$(mount | grep -E "/tmp/build|pimeleon" | awk '{print $3}' | sort -r)
    for mnt in $stale_mounts; do
        log_warn "Unmounting stale mount: $mnt"
        sudo umount -l "$mnt" 2>/dev/null || true
    done

    # Find and detach any leftover loop devices with pimeleon images
    for loop in $(losetup -l -n -O NAME,BACK-FILE 2>/dev/null | grep -i pimeleon | awk '{print $1}'); do
        log_warn "Detaching stale loop device: $loop"
        sudo kpartx -d "$loop" 2>/dev/null || true
        sudo losetup -d "$loop" 2>/dev/null || true
    done
}

# Check if running as root or with sudo
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root or with sudo"
    fi
}

# Check prerequisites
check_prerequisites() {
    local required_commands=(
        "debootstrap"
        "qemu-arm-static"
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
    if [[ ! -f /usr/bin/qemu-arm-static ]]; then
        die "qemu-arm-static not found. Please install qemu-user-static package."
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
    local loop_device=$(sudo losetup -f --show "$image_path")

    # Scan for partitions
    sudo kpartx -av "$loop_device"
    sleep 2

    # Get partition devices
    local boot_part="/dev/mapper/$(basename $loop_device)p1"
    local root_part="/dev/mapper/$(basename $loop_device)p2"

    # Mount partitions
    sudo mkdir -p "$mount_point"
    sudo mount "$root_part" "$mount_point"
    sudo mkdir -p "$mount_point/boot"
    sudo mount "$boot_part" "$mount_point/boot"

    # Register for cleanup on error
    CLEANUP_MOUNT_POINT="$mount_point"
    CLEANUP_LOOP_DEVICE="$loop_device"

    echo "$loop_device"
}

# Unmount image partitions
unmount_image() {
    local mount_point=$1
    local loop_device=$2

    log_info "Unmounting image"

    # Unmount boot partition
    if mountpoint -q "$mount_point/boot" 2>/dev/null; then
        sudo umount "$mount_point/boot" || log_warn "Failed to unmount boot"
    fi

    # Unmount root partition
    if mountpoint -q "$mount_point" 2>/dev/null; then
        sudo umount "$mount_point" || log_warn "Failed to unmount root"
    fi

    # Remove partition mappings
    if [[ -n "$loop_device" ]]; then
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

    # Copy qemu static binary
    sudo cp /usr/bin/qemu-arm-static "$chroot_dir/usr/bin/"

    # Mount special filesystems
    sudo mount -t proc proc "$chroot_dir/proc"
    sudo mount -t sysfs sys "$chroot_dir/sys"
    sudo mount -t devtmpfs dev "$chroot_dir/dev"
    sudo mount -t devpts devpts "$chroot_dir/dev/pts"

    # Write resolv.conf with real DNS servers (Docker's 127.0.0.11 doesn't work in chroot)
    sudo tee "$chroot_dir/etc/resolv.conf" > /dev/null <<EOF
# DNS for chroot build environment
nameserver 192.168.42.1
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

    # Track chroot state for cleanup
    CLEANUP_CHROOT_ACTIVE=true
}

# Cleanup chroot environment
cleanup_chroot() {
    local chroot_dir=$1

    log_info "Cleaning up chroot environment"

    # Unmount special filesystems (reverse order)
    sudo umount "$chroot_dir/dev/pts" 2>/dev/null || true
    sudo umount "$chroot_dir/dev" 2>/dev/null || true
    sudo umount "$chroot_dir/sys" 2>/dev/null || true
    sudo umount "$chroot_dir/proc" 2>/dev/null || true

    # Remove qemu static binary
    sudo rm -f "$chroot_dir/usr/bin/qemu-arm-static"

    # Clear chroot tracking
    CLEANUP_CHROOT_ACTIVE=false
}

# Run command in chroot
chroot_run() {
    local chroot_dir=$1
    shift

    sudo DEBIAN_FRONTEND=noninteractive chroot "$chroot_dir" "$@"
}

# Generate image metadata
generate_metadata() {
    local image_path=$1
    local metadata_file="${image_path}.metadata.json"

    log_info "Generating metadata: $metadata_file"

    # Calculate checksums
    local md5sum=$(md5sum "$image_path" | cut -d' ' -f1)
    local sha256sum=$(sha256sum "$image_path" | cut -d' ' -f1)
    local size=$(stat -c%s "$image_path")

    # Create metadata JSON
    cat > "$metadata_file" <<EOF
{
    "version": "$(date +%Y%m%d-%H%M%S)",
    "build_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "image_name": "$(basename $image_path)",
    "image_size": $size,
    "checksums": {
        "md5": "$md5sum",
        "sha256": "$sha256sum"
    },
    "build_info": {
        "rpi_model": "${PIMELEON_RPI_MODEL:-3B+}",
        "raspbian_version": "${RASPBIAN_VERSION:-buster}",
        "builder_version": "1.0.0"
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
    local workspace_dir="${WORKSPACE_DIR:-/workspace}"
    local app_dir="${workspace_dir}/apps/${app_name}"

    if [[ -z "$app_name" ]]; then
        die "App name is required"
    fi

    if [[ ! -d "$app_dir" ]]; then
        log_error "App not found: $app_name"
        list_apps
        die "Please specify a valid app name"
    fi

    # Parse app name: {device}-{debian}
    local device="${app_name%%-*}"      # rpi3, rpi4
    local debian="${app_name##*-}"      # bookworm

    # Derive configuration from device
    case "$device" in
        rpi3)
            export PIMELEON_RPI_MODEL="3B+"
            export RPI_ARCH="armhf"
            ;;
        rpi4)
            export PIMELEON_RPI_MODEL="4B"
            export RPI_ARCH="arm64"
            ;;
        *)
            die "Unknown device: $device (expected rpi3, rpi4)"
            ;;
    esac

    export RASPBIAN_VERSION="$debian"
    export PIMELEON_IMAGE_SIZE="${PIMELEON_IMAGE_SIZE:-4G}"

    log_info "App: ${app_name}"
    log_info "  Model: ${PIMELEON_RPI_MODEL}, Arch: ${RPI_ARCH}, Debian: ${RASPBIAN_VERSION}"
}

# List available apps
list_apps() {
    local workspace_dir="${WORKSPACE_DIR:-/workspace}"
    local apps_dir="${workspace_dir}/apps"

    if [[ ! -d "$apps_dir" ]]; then
        log_warn "No apps directory found at: $apps_dir"
        return 1
    fi

    echo ""
    echo "Available apps:"
    echo "==============="
    for app_dir in "$apps_dir"/*/; do
        [[ -d "$app_dir" ]] || continue
        local name=$(basename "$app_dir")
        local device="${name%%-*}"
        local debian="${name##*-}"
        printf "  %-20s (%s, %s)\n" "$name" "$device" "$debian"
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
    local cache_path=$(get_cache_path "$cache_key")
    [[ -f "$cache_path" ]]
}

cache_get() {
    local cache_key=$1
    local destination=$2
    local cache_path=$(get_cache_path "$cache_key")

    if cache_exists "$cache_key"; then
        log_info "Using cached file: $cache_key"
        sudo cp "$cache_path" "$destination"
        sudo chown builder:docker "$destination"
        return 0
    else
        return 1
    fi
}

cache_put() {
    local source=$1
    local cache_key=$2
    local cache_path=$(get_cache_path "$cache_key")

    log_info "Caching file: $cache_key"
    sudo mkdir -p "$(dirname $cache_path)"
    sudo cp "$source" "$cache_path"
    sudo chown builder:docker "$cache_path"
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

    log_info "Fetching ${package} (${arch}) from GitHub releases"
    http_code=$(curl -sL \
        "${auth_args[@]}" \
        -o "${download_dir}/${package}.tar.gz" \
        -w "%{http_code}" \
        "${asset_url}")
    if [[ "${http_code}" != "200" ]]; then
        log_error "Failed to download ${package} from GitHub: HTTP ${http_code}"
        log_error "URL: ${asset_url}"
        return 1
    fi

    log_info "Fetched ${package} from GitHub -> ${download_dir}/${package}.tar.gz"
    return 0
}

# Get a pre-built binary package from the appropriate source based on build context.
# CI development builds (MR to release/*): GitLab package registry.
# CI production builds (tag or push to release/*): GitHub releases.
# Local builds: local mounted pi-router-apps path, then GitLab registry as fallback.
# Source can be forced via PIMELEON_APPS_SOURCE=gitlab|github.
# Usage: get_pimeleon_apps_artifact <package> <arch> <download_dir>
get_pimeleon_apps_artifact() {
    local package="$1"
    local arch="$2"
    local download_dir="$3"
    local local_path="${PIMELEON_APPS_LOCAL_PATH:-/workspace/pi-router-apps}"

    # 1. CI environment: PIMELEON_APPS_SOURCE must be set (via CI rules variables)
    if [[ -n "${CI:-}" ]] || [[ -n "${GITLAB_CI:-}" ]]; then
        [[ -n "${PIMELEON_APPS_SOURCE:-}" ]] || die "PIMELEON_APPS_SOURCE is not set — must be 'gitlab' or 'github'"

        case "${PIMELEON_APPS_SOURCE}" in
            github)
                log_info "CI (production): fetching ${package} from GitHub releases"
                fetch_pimeleon_apps_github "$package" "$arch" "$download_dir"
                return $?
                ;;
            gitlab)
                log_info "CI (development): fetching ${package} from GitLab registry"
                fetch_pimeleon_apps "$package" "$arch" "$download_dir"
                return $?
                ;;
            *)
                die "Unknown PIMELEON_APPS_SOURCE '${PIMELEON_APPS_SOURCE}' — must be 'gitlab' or 'github'"
                ;;
        esac
    fi

    # 2. Local environment: Prioritize local cache if directory exists
    if [[ -d "${local_path}" ]]; then
        log_info "Checking local apps cache for ${package} in ${local_path}"
        # Expected local format: ${package}/${arch}/${package}.tar.gz
        # or simplified: ${package}.tar.gz in package dir
        local local_file
        if [[ -f "${local_path}/${package}/${arch}/${package}.tar.gz" ]]; then
            local_file="${local_path}/${package}/${arch}/${package}.tar.gz"
        elif [[ -f "${local_path}/${package}/${package}.tar.gz" ]]; then
            local_file="${local_path}/${package}/${package}.tar.gz"
        fi

        if [[ -n "${local_file:-}" ]]; then
            log_info "Using local artifact: ${local_file}"
            sudo cp "${local_file}" "${download_dir}/${package}.tar.gz"
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

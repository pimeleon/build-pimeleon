#!/bin/bash
# Common functions for Pimeleon build scripts

# Project name for cache keys and output naming
PIMELEON_PROJECT_NAME="${PIMELEON_PROJECT_NAME:-pimeleon}"

# Ownership configuration
PIMELEON_USER="${PIMELEON_USER:-$(id -u)}"
PIMELEON_GROUP="${PIMELEON_GROUP:-docker}"

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
CLEANUP_MOUNT_POINT="${CLEANUP_MOUNT_POINT:-}"
CLEANUP_LOOP_DEVICE="${CLEANUP_LOOP_DEVICE:-}"
CLEANUP_CHROOT_ACTIVE="${CLEANUP_CHROOT_ACTIVE:-false}"
CLEANUP_IMAGE_PATH="${CLEANUP_IMAGE_PATH:-}"
declare -a MOUNT_STACK=()

# Safe remove helper - prevents accidental deletion outside build directory
safe_rm() {
    local path=$1
    local work_dir_base="/tmp/build"
    local output_dir_base="/output"

    if [[ -z "$path" ]]; then
        log_warn "safe_rm: empty path provided, ignoring"
        return
    fi

        # Only allow deletion within sanctioned directories
        if [[ "$path" == "${work_dir_base}"* ]] || \
           [[ -n "${WORK_DIR:-}" && "$path" == "${WORK_DIR}"* ]] || \
           [[ "$path" == "${output_dir_base}"* ]] || \
           [[ -n "${OUTPUT_DIR:-}" && "$path" == "${OUTPUT_DIR}"* ]]; then

            # Proactively find and unmount any sub-mounts under this path
            local nested_mounts
            nested_mounts=$(findmnt -n -o TARGET -R "$path" 2>/dev/null | sort -r || true)
            if [[ -n "$nested_mounts" ]]; then
                log_warn "safe_rm: Found active mounts under $path, unmounting..."
                for mnt in $nested_mounts; do
                    sudo umount "$mnt" 2>/dev/null || sudo umount -l "$mnt" 2>/dev/null || true
                done
            fi

            # We allow glob expansion here by not quoting $path in the final command        # but the check above ensures the prefix is safe.
        # shellcheck disable=SC2086
        sudo rm -rf $path
    else
        die "CRITICAL: Attempted to delete path outside sanctioned directories: $path"
    fi
}
# Cleanup function for trap handlers
cleanup_on_exit() {
    local exit_code=$?
    set +e # Don't exit on error during cleanup

    # Only cleanup if we have something to clean
    if [[ -n "$CLEANUP_MOUNT_POINT" ]] || [[ -n "$CLEANUP_LOOP_DEVICE" ]] || [[ ${#MOUNT_STACK[@]} -gt 0 ]]; then
        log_warn "Cleanup triggered (exit code/signal: $exit_code)"

        # Cleanup chroot first if active
        if [[ "$CLEANUP_CHROOT_ACTIVE" == "true" ]]; then
            log_info "Cleaning up chroot before exit..."
            cleanup_chroot "$CLEANUP_MOUNT_POINT" || true
        fi

        # Unmount image (processed via stack)
        log_info "Releasing image resources..."
        unmount_image "$CLEANUP_MOUNT_POINT" "$CLEANUP_LOOP_DEVICE" || true
    fi

    # On failure (non-zero exit code)
    if [[ $exit_code -ne 0 ]]; then
        log_error "Failure detected (exit code: $exit_code)."
        if [[ -n "${LOG_FILE:-}" ]]; then
            log_error "Detailed build log: ${LOG_FILE}"
        fi

        if [[ -n "${CLEANUP_IMAGE_PATH:-}" ]]; then
            if [[ -f "$CLEANUP_IMAGE_PATH" ]]; then
                log_warn "Removing partial image: $CLEANUP_IMAGE_PATH"
                safe_rm "$CLEANUP_IMAGE_PATH"
                safe_rm "${CLEANUP_IMAGE_PATH}.xz"
                safe_rm "${CLEANUP_IMAGE_PATH}.sha256"
            fi
        fi
    fi

    # Exit with original code
    exit $exit_code
}

# Check if a service is enabled in the current profile
is_service_enabled() {
    local service_name=$1
    local profile_path="${ANSIBLE_DIR:-/workspace/shared/ansible}/vars/common/profiles/${PIMELEON_PROFILE:-development}.yml"

    if [[ ! -f "$profile_path" ]]; then
        log_warn "Profile file not found: $profile_path"
        return 1
    fi

    # Use Python for robust YAML parsing (available in builder image)
    if python3 -c "import yaml; import os; profile = yaml.safe_load(open('$profile_path')) if os.path.exists('$profile_path') else {}; exit(0 if profile.get('services_enabled', {}).get('$service_name') == True else 1)" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Check if a service should be built from source in the current profile
is_build_from_source_enabled() {
    local service_name=$1
    local profile_path="${ANSIBLE_DIR:-/workspace/shared/ansible}/vars/common/profiles/${PIMELEON_PROFILE:-development}.yml"
    local versions_path="${ANSIBLE_DIR:-/workspace/shared/ansible}/vars/common/versions.yml"

    # Check profile first, then fallback to versions.yml
    if python3 -c "
import yaml
import sys
import os

def get_val(path, section, key):
    try:
        if not os.path.exists(path): return None
        with open(path, 'r') as f:
            data = yaml.safe_load(f)
            return data.get(section, {}).get(key)
    except Exception: return None

# Try profile override
val = get_val('$profile_path', 'build_from_source', '$service_name')
if val is not None: sys.exit(0 if val == True else 1)

# Fallback to versions.yml
val = get_val('$versions_path', 'build_from_source', '$service_name')
sys.exit(0 if val == True else 1)
" 2>/dev/null; then
        return 0
    else
        return 1
    fi
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
            sudo umount -l "$mnt" 2>/dev/null || true
        done
    fi

    # Find and detach any leftover loop devices with pimeleon images
    # Check for both the image name and the mount point path
    local stale_loops
    stale_loops=$(losetup -l -n -O NAME,BACK-FILE 2>/dev/null | grep -E "pimeleon|${work_dir_base}" | awk '{print $1}' || true)
    if [[ -n "$stale_loops" ]]; then
        for loop in $stale_loops; do
            log_warn "Detaching stale loop device: $loop"
            sudo kpartx -d "$loop" 2>/dev/null || true
            sudo losetup -d "$loop" 2>/dev/null || true
        done
    fi
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
    local loop_device
    loop_device=$(sudo losetup -f --show "$image_path")

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

    # Copy qemu static binary
    sudo cp /usr/bin/qemu-arm-static "$chroot_dir/usr/bin/"

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
    sudo rm -f "$chroot_dir/usr/bin/qemu-arm-static"

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
    if [[ -n "${APT_CACHE_SERVER:-}" ]]; then
        # Try to connect to the APT Cache port (TCP)
        if timeout 1 bash -c "cat < /dev/null > /dev/tcp/${APT_CACHE_SERVER}/${APT_CACHE_PORT:-3142}" 2>/dev/null; then
            log_info "APT Cache Server (${APT_CACHE_SERVER}) is reachable."
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
            if [[ -n "${APT_CACHE_SERVER:-}" ]]; then
                log_warn "Neither APT Cache Server (${APT_CACHE_SERVER}) nor Internet are reachable. Build might fail."
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
    if [[ -n "${APT_CACHE_SERVER:-}" ]]; then
        log_info "Configuring APT cache for chroot: ${APT_CACHE_SERVER}:${APT_CACHE_PORT:-3142}"
        sudo mkdir -p "${mount_point}/etc/apt/apt.conf.d"
        sudo tee "${mount_point}/etc/apt/apt.conf.d/01proxy" > /dev/null <<EOF
# APT Cache Configuration for Build Process
Acquire::http::Proxy "http://${APT_CACHE_SERVER}:${APT_CACHE_PORT:-3142}";
# Longer timeouts for slow cache/upstream responses
Acquire::http::Timeout "120";
Acquire::https::Timeout "120";
Acquire::Retries "3";
EOF
    fi
}

# Remove APT cache proxy from chroot
remove_chroot_apt_proxy() {
    local mount_point=$1
    if [[ -f "${mount_point}/etc/apt/apt.conf.d/01proxy" ]]; then
        log_info "Removing APT cache configuration from chroot"
        sudo rm -f "${mount_point}/etc/apt/apt.conf.d/01proxy"
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
    if [[ -n "${APT_CACHE_SERVER:-}" ]]; then
        local proxy_url="http://${APT_CACHE_SERVER}:${APT_CACHE_PORT:-3142}"
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
    "image_name": "$(basename "$image_path")",
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
        local name
        name=$(basename "$app_dir")
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

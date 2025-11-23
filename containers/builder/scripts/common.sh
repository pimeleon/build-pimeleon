#!/bin/bash
# Common functions for Pimeleon build scripts

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
    
    echo "$loop_device"
}

# Unmount image partitions
unmount_image() {
    local mount_point=$1
    local loop_device=$2
    
    log_info "Unmounting image"
    
    # Unmount partitions
    sudo umount "$mount_point/boot" || true
    sudo umount "$mount_point" || true
    
    # Remove partition mappings
    sudo kpartx -d "$loop_device" || true
    
    # Detach loop device
    sudo losetup -d "$loop_device" || true
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
    
    # Copy resolv.conf
    sudo cp /etc/resolv.conf "$chroot_dir/etc/resolv.conf"
}

# Cleanup chroot environment
cleanup_chroot() {
    local chroot_dir=$1
    
    log_info "Cleaning up chroot environment"
    
    # Unmount special filesystems
    sudo umount "$chroot_dir/dev/pts" || true
    sudo umount "$chroot_dir/dev" || true
    sudo umount "$chroot_dir/sys" || true
    sudo umount "$chroot_dir/proc" || true
    
    # Remove qemu static binary
    sudo rm -f "$chroot_dir/usr/bin/qemu-arm-static"
}

# Run command in chroot
chroot_run() {
    local chroot_dir=$1
    shift
    
    sudo chroot "$chroot_dir" "$@"
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

# Cache management
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
        sudo chown builder:builder "$destination"
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
    sudo chown builder:builder "$cache_path"
}
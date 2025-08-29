#!/bin/bash
set -euo pipefail

# Stage 1: Create base system
# Creates the base Raspbian image with partitions

source /scripts/common.sh

WORK_DIR=$1
IMAGE_PATH=$2
IMAGE_SIZE=$3

# Validate parameters
if [[ -z "$WORK_DIR" || -z "$IMAGE_PATH" || -z "$IMAGE_SIZE" ]]; then
    die "Usage: $0 <work_dir> <image_path> <image_size>"
fi

MOUNT_POINT="${WORK_DIR}/mount"
RASPBIAN_CACHE_KEY="raspbian-${RASPBIAN_VERSION}-base.tar.gz"

log_info "Creating image file: ${IMAGE_PATH}"

# Create image file - parse size properly
SIZE_MB=$(echo "${IMAGE_SIZE}" | sed 's/G/*1024/' | sed 's/M//' | bc)
log_info "Creating ${SIZE_MB}MB image file"

# Ensure output directory exists and has proper permissions
sudo mkdir -p "$(dirname "${IMAGE_PATH}")"
sudo chown builder:builder "$(dirname "${IMAGE_PATH}")"

# Create sparse image file
if ! sudo dd if=/dev/zero of="${IMAGE_PATH}" bs=1M count=1 seek=$((SIZE_MB - 1)); then
    die "Failed to create image file: ${IMAGE_PATH}"
fi

# Verify file was created with correct size
if [[ ! -f "${IMAGE_PATH}" ]]; then
    die "Image file was not created: ${IMAGE_PATH}"
fi

ACTUAL_SIZE=$(stat -c%s "${IMAGE_PATH}")
EXPECTED_SIZE=$((SIZE_MB * 1024 * 1024))
if [[ $ACTUAL_SIZE -ne $EXPECTED_SIZE ]]; then
    die "Image file has wrong size: ${ACTUAL_SIZE} bytes, expected ${EXPECTED_SIZE} bytes"
fi

log_info "Successfully created ${SIZE_MB}MB image file"

# Create partitions
log_info "Creating partitions"
sudo parted -s "${IMAGE_PATH}" mklabel msdos
sudo parted -s "${IMAGE_PATH}" mkpart primary fat32 1MiB 256MiB
sudo parted -s "${IMAGE_PATH}" mkpart primary ext4 256MiB 100%
sudo parted -s "${IMAGE_PATH}" set 1 boot on

# Setup loop device and format partitions
LOOP_DEVICE=$(sudo losetup -f --show "${IMAGE_PATH}")
sudo kpartx -av "${LOOP_DEVICE}"
sleep 2

BOOT_PART="/dev/mapper/$(basename ${LOOP_DEVICE})p1"
ROOT_PART="/dev/mapper/$(basename ${LOOP_DEVICE})p2"

log_info "Formatting partitions"
sudo mkfs.vfat -F 32 -n BOOT "${BOOT_PART}"
sudo mkfs.ext4 -L rootfs "${ROOT_PART}"

# Mount partitions
sudo mkdir -p "${MOUNT_POINT}"
sudo mount "${ROOT_PART}" "${MOUNT_POINT}"
sudo mkdir -p "${MOUNT_POINT}/boot"
sudo mount "${BOOT_PART}" "${MOUNT_POINT}/boot"

# Check cache for base system
if cache_exists "${RASPBIAN_CACHE_KEY}"; then
    log_info "Using cached Raspbian base system"
    cache_get "${RASPBIAN_CACHE_KEY}" "${WORK_DIR}/raspbian-base.tar.gz"
    sudo tar -xzf "${WORK_DIR}/raspbian-base.tar.gz" -C "${MOUNT_POINT}"
else
    log_info "Bootstrapping Raspbian ${RASPBIAN_VERSION}"
    
    # First stage debootstrap with keyring handling
    # For Raspbian, disable GPG verification as keyring is not readily available in Debian
    KEYRING_OPT="--no-check-gpg"
    log_warn "Disabling GPG verification for Raspbian bootstrap"
    
    # ARM binary format registration handled by host system
    # Host should have: sudo apt install binfmt-support qemu-user-static
    log_info "Relying on host system ARM binary format registration"
    
    # Bootstrap base system without Pi-specific packages first
    # Exclude DHCP packages since systemd handles networking
    sudo debootstrap --foreign --arch=armhf \
        --exclude=isc-dhcp-common,isc-dhcp-client \
        ${KEYRING_OPT} \
        "${RASPBIAN_VERSION}" "${MOUNT_POINT}" "${RASPBIAN_MIRROR}"
    
    # Setup chroot for second stage
    setup_chroot "${MOUNT_POINT}"
    
    # Second stage debootstrap
    chroot_run "${MOUNT_POINT}" /debootstrap/debootstrap --second-stage
    
    # Configure apt sources with all required components
    sudo tee "${MOUNT_POINT}/etc/apt/sources.list" > /dev/null <<EOF
deb ${RASPBIAN_MIRROR} ${RASPBIAN_VERSION} main contrib non-free rpi
deb-src ${RASPBIAN_MIRROR} ${RASPBIAN_VERSION} main contrib non-free rpi
EOF
    
    # Cache the base system
    log_info "Caching base system for future builds"
    sudo tar -czf "${WORK_DIR}/raspbian-base.tar.gz" -C "${MOUNT_POINT}" .
    cache_put "${WORK_DIR}/raspbian-base.tar.gz" "${RASPBIAN_CACHE_KEY}"
    
    # Cleanup chroot
    cleanup_chroot "${MOUNT_POINT}"
fi

# Configure boot
log_info "Configuring boot"
sudo tee "${MOUNT_POINT}/boot/config.txt" > /dev/null <<EOF
# Pi Router Boot Configuration
enable_uart=1
dtparam=spi=on
dtparam=i2c_arm=on
gpu_mem=16
max_usb_current=1

# Network boot settings
boot_delay=1

# CPU settings
arm_freq=1200
over_voltage=2
EOF

# Configure cmdline
echo "console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait quiet" | sudo tee "${MOUNT_POINT}/boot/cmdline.txt" > /dev/null

# Basic fstab
sudo tee "${MOUNT_POINT}/etc/fstab" > /dev/null <<EOF
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p1  /boot           vfat    defaults          0       2
/dev/mmcblk0p2  /               ext4    defaults,noatime  0       1
EOF

# Set hostname
echo "pimeleon" | sudo tee "${MOUNT_POINT}/etc/hostname" > /dev/null

# Unmount
sudo umount "${MOUNT_POINT}/boot"
sudo umount "${MOUNT_POINT}"
sudo kpartx -d "${LOOP_DEVICE}"
sudo losetup -d "${LOOP_DEVICE}"

log_info "Stage 1 completed successfully"
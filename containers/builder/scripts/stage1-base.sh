#!/bin/bash
set -euo pipefail

# Stage 1: Create base system
# Creates the base Raspbian image with partitions

source /scripts/common.sh

WORK_DIR=$1
IMAGE_PATH=$2
IMAGE_SIZE=$3

MOUNT_POINT="${WORK_DIR}/mount"
RASPBIAN_CACHE_KEY="raspbian-${RASPBIAN_VERSION}-base.tar.gz"

log_info "Creating image file: ${IMAGE_PATH}"

# Create image file
sudo dd if=/dev/zero of="${IMAGE_PATH}" bs=1M count=0 seek=$(echo $IMAGE_SIZE | sed 's/G/*1024/g' | bc)

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
    
    # First stage debootstrap
    sudo debootstrap --foreign --arch=armhf \
        --include=raspberrypi-bootloader,raspberrypi-kernel \
        "${RASPBIAN_VERSION}" "${MOUNT_POINT}" "${RASPBIAN_MIRROR}"
    
    # Setup chroot for second stage
    setup_chroot "${MOUNT_POINT}"
    
    # Second stage debootstrap
    chroot_run "${MOUNT_POINT}" /debootstrap/debootstrap --second-stage
    
    # Cache the base system
    log_info "Caching base system for future builds"
    sudo tar -czf "${WORK_DIR}/raspbian-base.tar.gz" -C "${MOUNT_POINT}" .
    cache_put "${WORK_DIR}/raspbian-base.tar.gz" "${RASPBIAN_CACHE_KEY}"
    
    # Cleanup chroot
    cleanup_chroot "${MOUNT_POINT}"
fi

# Configure boot
log_info "Configuring boot"
cat > "${MOUNT_POINT}/boot/config.txt" <<EOF
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
echo "console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait quiet" > "${MOUNT_POINT}/boot/cmdline.txt"

# Basic fstab
cat > "${MOUNT_POINT}/etc/fstab" <<EOF
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p1  /boot           vfat    defaults          0       2
/dev/mmcblk0p2  /               ext4    defaults,noatime  0       1
EOF

# Set hostname
echo "pi-router" > "${MOUNT_POINT}/etc/hostname"

# Unmount
sudo umount "${MOUNT_POINT}/boot"
sudo umount "${MOUNT_POINT}"
sudo kpartx -d "${LOOP_DEVICE}"
sudo losetup -d "${LOOP_DEVICE}"

log_info "Stage 1 completed successfully"
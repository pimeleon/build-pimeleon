#!/bin/bash
set -euo pipefail

# Stage 1: Create base system
# Creates the base Raspbian image with partitions

# shellcheck disable=SC1091
# shellcheck disable=SC1091
source /scripts/common.sh

# Setup cleanup trap for error handling
trap 'cleanup_on_exit' EXIT ERR INT TERM

WORK_DIR=$1
IMAGE_PATH=$2
IMAGE_SIZE=$3

# Validate parameters
if [[ -z "$WORK_DIR" || -z "$IMAGE_PATH" || -z "$IMAGE_SIZE" ]]; then
    die "Usage: $0 <work_dir> <image_path> <image_size>"
fi

MOUNT_POINT="${WORK_DIR}/mount"
CACHE_VERSION="v4"  # v2: python3-minimal, v3: modern GPG keyring (no apt-key), v4: legacy keyring migration
# Normalize PIMELEON_RPI_MODEL for cache naming (3B+ -> rpi3, 4B -> rpi4, etc.)
RPI_CACHE_NAME=$(echo "${PIMELEON_RPI_MODEL}" | sed -E 's/^([0-9]+).*/rpi\1/')
RASPBIAN_CACHE_KEY="${PIMELEON_PROJECT_NAME}-${RPI_CACHE_NAME}-${RASPBIAN_VERSION}-base-${CACHE_VERSION}.tar.gz"

log_info "Creating image file: ${IMAGE_PATH}"

# Create image file - parse size properly
SIZE_MB=$(echo "${IMAGE_SIZE}" | sed 's/G/*1024/' | sed 's/M//' | bc)
log_info "Creating ${SIZE_MB}MB image file"

# Ensure output directory exists and has proper permissions
mkdir -p "$(dirname "${IMAGE_PATH}")"
sudo chown "${PIMELEON_USER}:${PIMELEON_GROUP}" "$(dirname "${IMAGE_PATH}")"

# Create sparse image file
if ! truncate -s "${IMAGE_SIZE}" "${IMAGE_PATH}"; then
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
# Register loop device for cleanup immediately to prevent leaks on mkfs failure
CLEANUP_LOOP_DEVICE="${LOOP_DEVICE}"

sudo kpartx -av "${LOOP_DEVICE}"
sleep 2

BOOT_PART="/dev/mapper/$(basename "${LOOP_DEVICE}")p1"
ROOT_PART="/dev/mapper/$(basename "${LOOP_DEVICE}")p2"

log_info "Formatting partitions"
sudo mkfs.vfat -F 32 -n BOOT "${BOOT_PART}"
sudo mkfs.ext4 -L rootfs "${ROOT_PART}"

# Mount partitions
sudo mkdir -p "${MOUNT_POINT}"
sudo mount "${ROOT_PART}" "${MOUNT_POINT}"
sudo mkdir -p "${MOUNT_POINT}/boot"
sudo mount "${BOOT_PART}" "${MOUNT_POINT}/boot"

# Register mount point for cleanup
CLEANUP_MOUNT_POINT="${MOUNT_POINT}"

# Check cache for base system
if cache_exists "${RASPBIAN_CACHE_KEY}"; then
    log_info "Using cached Raspbian base system"
    cache_get "${RASPBIAN_CACHE_KEY}" "${WORK_DIR}/raspbian-base.tar.gz"
    sudo tar -xzf "${WORK_DIR}/raspbian-base.tar.gz" -C "${MOUNT_POINT}"
else
    # Determine architecture-specific settings
    DEBOOTSTRAP_ARCH="${RPI_ARCH:-armhf}"
    if [[ "${DEBOOTSTRAP_ARCH}" == "arm64" ]]; then
        # arm64 uses standard Debian repos (Raspbian is armhf-only)
        DEBOOTSTRAP_MIRROR="http://deb.debian.org/debian"
        log_info "Bootstrapping Debian ${RASPBIAN_VERSION} (${DEBOOTSTRAP_ARCH})"
    else
        # armhf uses Raspbian repos
        DEBOOTSTRAP_MIRROR="${RASPBIAN_MIRROR}"
        log_info "Bootstrapping Raspbian ${RASPBIAN_VERSION} (${DEBOOTSTRAP_ARCH})"
    fi

    # First stage debootstrap with keyring handling
    KEYRING_OPT=""
    if [[ "${DEBOOTSTRAP_ARCH}" != "arm64" ]]; then
        # For Raspbian, disable GPG verification as keyring is not readily available in Debian
        KEYRING_OPT="--no-check-gpg"
        log_warn "Disabling GPG verification for Raspbian bootstrap"
    fi

    # ARM binary format registration handled by host system
    # Host should have: sudo apt install binfmt-support qemu-user-static
    log_info "Relying on host system ARM binary format registration"

    # Configure proxy environment for debootstrap if available
    DEBOOTSTRAP_ENV=""
    if has_apt_proxy; then
        log_info "Configuring APT proxy for debootstrap: ${APT_PROXY}"
        DEBOOTSTRAP_ENV="http_proxy=http://${APT_PROXY} HTTP_PROXY=http://${APT_PROXY}"
    fi

    # Bootstrap base system without Pi-specific packages first
    # Include python3-minimal for Ansible compatibility
    # Exclude DHCP packages since systemd handles networking
    # shellcheck disable=SC2086  # word splitting intentional: expands proxy vars or nothing when empty
    sudo env ${DEBOOTSTRAP_ENV} debootstrap --foreign --arch="${DEBOOTSTRAP_ARCH}" \
        --include=python3-minimal \
        --exclude=isc-dhcp-common,isc-dhcp-client \
        ${KEYRING_OPT} \
        "${RASPBIAN_VERSION}" "${MOUNT_POINT}" "${DEBOOTSTRAP_MIRROR}"

    # Setup chroot for second stage
    setup_chroot "${MOUNT_POINT}"

    # Configure proxy for second stage debootstrap if available
    configure_chroot_apt_proxy "${MOUNT_POINT}"

    # Second stage debootstrap
    chroot_run "${MOUNT_POINT}" /debootstrap/debootstrap --second-stage

    # Remove temporary proxy config
    remove_chroot_apt_proxy "${MOUNT_POINT}"

    # Configure apt sources based on architecture
    if [[ "${DEBOOTSTRAP_ARCH}" == "arm64" ]]; then
        # arm64: standard Debian repos + non-free-firmware for bookworm+
        sudo tee "${MOUNT_POINT}/etc/apt/sources.list" > /dev/null <<EOF
deb http://deb.debian.org/debian ${RASPBIAN_VERSION} main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security ${RASPBIAN_VERSION}-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${RASPBIAN_VERSION}-updates main contrib non-free non-free-firmware
EOF
    else
        # armhf: Raspbian repos
        sudo tee "${MOUNT_POINT}/etc/apt/sources.list" > /dev/null <<EOF
deb ${RASPBIAN_MIRROR} ${RASPBIAN_VERSION} main contrib non-free rpi
deb-src ${RASPBIAN_MIRROR} ${RASPBIAN_VERSION} main contrib non-free rpi
EOF
    fi

    # Add Raspberry Pi Foundation GPG key (modern method - no apt-key)
    sudo mkdir -p "${MOUNT_POINT}/etc/apt/keyrings"
    wget -qO- https://archive.raspberrypi.com/debian/raspberrypi.gpg.key | \
        gpg --dearmor | \
        sudo tee "${MOUNT_POINT}/etc/apt/keyrings/raspberrypi-archive-keyring.gpg" > /dev/null \
        || die "Failed to fetch or install Raspberry Pi GPG keyring"
    sudo chmod 644 "${MOUNT_POINT}/etc/apt/keyrings/raspberrypi-archive-keyring.gpg"

    # Add Raspberry Pi Foundation repository for kernel and firmware (with signed-by)
    sudo tee "${MOUNT_POINT}/etc/apt/sources.list.d/raspi.list" > /dev/null <<EOF
deb [signed-by=/etc/apt/keyrings/raspberrypi-archive-keyring.gpg] http://archive.raspberrypi.com/debian/ ${RASPBIAN_VERSION} main
EOF

    # Configure APT cache for chroot if available
    configure_chroot_apt_proxy "${MOUNT_POINT}"

    # Migrate legacy APT keyring to modern format (prevents deprecation warnings)
    migrate_apt_keyring "${MOUNT_POINT}"

    # Cache the base system
    log_info "Caching base system for future builds"
    sudo tar -czf "${WORK_DIR}/raspbian-base.tar.gz" -C "${MOUNT_POINT}" .
    cache_put "${WORK_DIR}/raspbian-base.tar.gz" "${RASPBIAN_CACHE_KEY}"

    # Cleanup chroot
    cleanup_chroot "${MOUNT_POINT}"
fi

# Configure basic boot files (firmware will be installed in stage2)
log_info "Configuring basic boot files"
sudo tee "${MOUNT_POINT}/boot/config.txt" > /dev/null <<EOF
# Pimeleon Boot Configuration
# Optimized for Raspberry Pi 3B+

# Disable rainbow splash for clean boot
disable_splash=1

# Display settings
hdmi_force_hotplug=1
hdmi_drive=2
config_hdmi_boost=4

# Optimized performance settings
arm_freq=1000
over_voltage=2

# Essential hardware interfaces
dtparam=i2c_arm=on
dtparam=spi=on

# Enable KMS driver for GPU acceleration
dtoverlay=vc4-fkms-v3d

# Disable all multimedia and camera features
dtparam=audio=off
start_x=0

# System constraints
enable_uart=0
gpu_mem=128
max_usb_current=1

# Boot timing
boot_delay=0
EOF

# Configure cmdline
echo "console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait fsck.mode=force ipv6.disable=0 net.ifnames=0 brcmfmac.txglomsz=32 loglevel=4 logo.nologo vt.global_cursor_default=1" | sudo tee "${MOUNT_POINT}/boot/cmdline.txt" > /dev/null

# Basic fstab with tmpfs for /tmp (reduces SD card wear)
sudo tee "${MOUNT_POINT}/etc/fstab" > /dev/null <<EOF
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p1  /boot           vfat    defaults          0       2
/dev/mmcblk0p2  /               ext4    defaults,noatime  0       1
tmpfs           /tmp            tmpfs   defaults,noatime,nosuid,nodev,noexec,mode=1777,size=100M 0 0
EOF

# Set hostname
echo "pimeleon" | sudo tee "${MOUNT_POINT}/etc/hostname" > /dev/null

# Verify stage completion
verify_stage 1 "${MOUNT_POINT}"

# Unmount
sudo umount "${MOUNT_POINT}/boot"
sudo umount "${MOUNT_POINT}"
sudo kpartx -d "${LOOP_DEVICE}"
sudo losetup -d "${LOOP_DEVICE}"

# Clear cleanup tracking (successful unmount)
# shellcheck disable=SC2034
CLEANUP_MOUNT_POINT=""
# shellcheck disable=SC2034
CLEANUP_LOOP_DEVICE=""

log_info "Stage 1 completed successfully"

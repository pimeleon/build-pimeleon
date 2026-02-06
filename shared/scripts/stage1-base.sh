#!/bin/bash
set -euo pipefail

# Stage 1: Create base system
# Creates the base Raspbian image with partitions

source /scripts/common.sh

# Setup cleanup trap for error handling
trap cleanup_on_exit EXIT ERR INT

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
sudo chown builder:docker "$(dirname "${IMAGE_PATH}")"

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

# Register mount point for cleanup
CLEANUP_MOUNT_POINT="${MOUNT_POINT}"

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

    # Configure proxy environment for debootstrap if available
    DEBOOTSTRAP_ENV=""
    if [[ -n "${APT_CACHE_SERVER:-}" ]]; then
        log_info "Configuring APT proxy for debootstrap: ${APT_CACHE_SERVER}:${APT_CACHE_PORT:-3142}"
        DEBOOTSTRAP_ENV="http_proxy=http://${APT_CACHE_SERVER}:${APT_CACHE_PORT:-3142} HTTP_PROXY=http://${APT_CACHE_SERVER}:${APT_CACHE_PORT:-3142}"
    fi

    # Bootstrap base system without Pi-specific packages first
    # Include python3-minimal for Ansible compatibility
    # Exclude DHCP packages since systemd handles networking
    sudo env ${DEBOOTSTRAP_ENV} debootstrap --foreign --arch=armhf \
        --include=python3-minimal \
        --exclude=isc-dhcp-common,isc-dhcp-client \
        ${KEYRING_OPT} \
        "${RASPBIAN_VERSION}" "${MOUNT_POINT}" "${RASPBIAN_MIRROR}"

    # Setup chroot for second stage
    setup_chroot "${MOUNT_POINT}"

    # Configure proxy for second stage debootstrap if available
    if [[ -n "${APT_CACHE_SERVER:-}" ]]; then
        sudo mkdir -p "${MOUNT_POINT}/etc/apt/apt.conf.d"
        sudo tee "${MOUNT_POINT}/etc/apt/apt.conf.d/01proxy-temp" > /dev/null <<EOF
# Temporary APT proxy for debootstrap second stage
Acquire::http::Proxy "http://${APT_CACHE_SERVER}:${APT_CACHE_PORT:-3142}";
Acquire::http::Timeout "120";
Acquire::https::Timeout "120";
Acquire::Retries "3";
EOF
    fi

    # Second stage debootstrap
    chroot_run "${MOUNT_POINT}" /debootstrap/debootstrap --second-stage

    # Remove temporary proxy config
    if [[ -n "${APT_CACHE_SERVER:-}" ]]; then
        sudo rm -f "${MOUNT_POINT}/etc/apt/apt.conf.d/01proxy-temp"
    fi

    # Configure apt sources with all required components
    sudo tee "${MOUNT_POINT}/etc/apt/sources.list" > /dev/null <<EOF
deb ${RASPBIAN_MIRROR} ${RASPBIAN_VERSION} main contrib non-free rpi
deb-src ${RASPBIAN_MIRROR} ${RASPBIAN_VERSION} main contrib non-free rpi
EOF

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
    if [[ -n "${APT_CACHE_SERVER:-}" ]]; then
        log_info "Configuring APT cache for chroot environment"
        sudo mkdir -p "${MOUNT_POINT}/etc/apt/apt.conf.d"
        sudo tee "${MOUNT_POINT}/etc/apt/apt.conf.d/01proxy" > /dev/null <<EOF
# APT Cache Configuration for Build Process
Acquire::http::Proxy "http://${APT_CACHE_SERVER}:${APT_CACHE_PORT:-3142}";
# Longer timeouts for slow cache/upstream responses
Acquire::http::Timeout "120";
Acquire::https::Timeout "120";
Acquire::Retries "3";
EOF
    fi

    # Migrate legacy APT keyring to modern format (prevents deprecation warnings)
    if [ -f "${MOUNT_POINT}/etc/apt/trusted.gpg" ]; then
        log_info "Migrating legacy APT keyring to modern format"
        sudo mkdir -p "${MOUNT_POINT}/etc/apt/trusted.gpg.d"
        sudo gpg --no-default-keyring \
            --keyring "${MOUNT_POINT}/etc/apt/trusted.gpg" \
            --export 2>/dev/null | \
            sudo gpg --no-default-keyring \
                --keyring "gnupg-ring:${MOUNT_POINT}/etc/apt/trusted.gpg.d/raspbian-archive-keyring.gpg" \
                --import 2>/dev/null || true
        sudo chmod 644 "${MOUNT_POINT}/etc/apt/trusted.gpg.d/raspbian-archive-keyring.gpg" 2>/dev/null || true
        sudo rm -f "${MOUNT_POINT}/etc/apt/trusted.gpg"
        log_info "Legacy keyring migrated and removed"
    fi

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

# Disable rainbow splash for clean boot
disable_splash=1

# uncomment if you get no picture on HDMI for a default "safe" mode
#hdmi_safe=1

# uncomment this if your display has a black border of unused pixels visible
# and your display can output without overscan
#disable_overscan=1

# uncomment the following to adjust overscan. Use positive numbers if console
# goes off screen, and negative if there is too much border
#overscan_left=16
#overscan_right=16
#overscan_top=16
#overscan_bottom=16

# uncomment to force a console size. By default it will be display's size minus
# overscan.
#framebuffer_width=1280
#framebuffer_height=720

# uncomment if hdmi display is not detected and composite is being output
hdmi_force_hotplug=1

# uncomment to force a specific HDMI mode (this will force VGA)
#hdmi_group=1
#hdmi_mode=4

# uncomment to force a HDMI mode rather than DVI. This can make audio work in
# DMT (computer monitor) modes
hdmi_drive=2

# uncomment to increase signal to HDMI, if you have interference, blanking, or
# no display
config_hdmi_boost=4

#uncomment to overclock the arm. 700 MHz is the default.
arm_freq=1000
over_voltage=2

# Uncomment some or all of these to enable the optional hardware interfaces
dtparam=i2c_arm=on
#dtparam=i2s=on
dtparam=spi=on

# Uncomment this to enable the lirc-rpi module
#dtoverlay=lirc-rpi

# Additional overlays and parameters are documented /boot/overlays/README

# Enable KMS driver for GPU acceleration
dtoverlay=vc4-fkms-v3d

# Enable audio (loads snd_bcm2835)
dtparam=audio=off
start_x=0

enable_uart=0
gpu_mem=256
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

# Unmount
sudo umount "${MOUNT_POINT}/boot"
sudo umount "${MOUNT_POINT}"
sudo kpartx -d "${LOOP_DEVICE}"
sudo losetup -d "${LOOP_DEVICE}"

# Clear cleanup tracking (successful unmount)
CLEANUP_MOUNT_POINT=""
CLEANUP_LOOP_DEVICE=""

log_info "Stage 1 completed successfully"

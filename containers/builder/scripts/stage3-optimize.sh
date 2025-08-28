#!/bin/bash
set -euo pipefail

# Stage 3: Optimize image
# Clean up and shrink the image

source /scripts/common.sh

WORK_DIR=$1
IMAGE_PATH=$2
MOUNT_POINT="${WORK_DIR}/mount"

log_info "Starting image optimization"

# Mount image
LOOP_DEVICE=$(mount_image "${IMAGE_PATH}" "${MOUNT_POINT}")

# Setup chroot
setup_chroot "${MOUNT_POINT}"

# Clean package cache
log_info "Cleaning package cache"
chroot_run "${MOUNT_POINT}" apt-get clean
chroot_run "${MOUNT_POINT}" apt-get autoclean
chroot_run "${MOUNT_POINT}" apt-get autoremove -y

# Remove unnecessary packages
log_info "Removing unnecessary packages"
chroot_run "${MOUNT_POINT}" apt-get purge -y \
    man-db \
    manpages \
    info \
    install-info \
    tasksel \
    tasksel-data || true

# Clear logs
log_info "Clearing logs"
find "${MOUNT_POINT}/var/log" -type f -exec truncate -s 0 {} \;

# Remove temporary files
log_info "Removing temporary files"
rm -rf "${MOUNT_POINT}/tmp/"*
rm -rf "${MOUNT_POINT}/var/tmp/"*
rm -rf "${MOUNT_POINT}/var/cache/apt/archives/"*.deb
rm -rf "${MOUNT_POINT}/var/lib/apt/lists/"*

# Remove documentation
log_info "Removing documentation"
rm -rf "${MOUNT_POINT}/usr/share/doc/"*
rm -rf "${MOUNT_POINT}/usr/share/man/"*
rm -rf "${MOUNT_POINT}/usr/share/info/"*
rm -rf "${MOUNT_POINT}/usr/share/lintian/"*

# Remove locales except en_US
log_info "Removing unused locales"
find "${MOUNT_POINT}/usr/share/locale" -mindepth 1 -maxdepth 1 ! -name 'en*' -exec rm -rf {} \;

# Configure locale
echo "en_US.UTF-8 UTF-8" > "${MOUNT_POINT}/etc/locale.gen"
chroot_run "${MOUNT_POINT}" locale-gen

# Remove SSH host keys (will be regenerated on first boot)
rm -f "${MOUNT_POINT}/etc/ssh/ssh_host_"*

# Create first boot script
log_info "Creating first boot script"
cat > "${MOUNT_POINT}/etc/systemd/system/firstboot.service" <<EOF
[Unit]
Description=First Boot Setup
After=network.target
ConditionPathExists=!/etc/firstboot.done

[Service]
Type=oneshot
ExecStart=/usr/local/bin/firstboot.sh
ExecStartPost=/bin/touch /etc/firstboot.done
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat > "${MOUNT_POINT}/usr/local/bin/firstboot.sh" <<'EOF'
#!/bin/bash
set -e

# Generate SSH host keys
ssh-keygen -A

# Expand root filesystem
raspi-config --expand-rootfs

# Generate machine ID
systemd-machine-id-setup

# Update package lists
apt-get update

# Set timezone
timedatectl set-timezone UTC

# Enable firewall
nft -f /etc/nftables.conf

echo "First boot setup completed"
EOF

chmod +x "${MOUNT_POINT}/usr/local/bin/firstboot.sh"
chroot_run "${MOUNT_POINT}" systemctl enable firstboot.service

# Zero free space for better compression
log_info "Zeroing free space"
dd if=/dev/zero of="${MOUNT_POINT}/zero.file" bs=1M || true
rm -f "${MOUNT_POINT}/zero.file"

# Cleanup chroot
cleanup_chroot "${MOUNT_POINT}"

# Get filesystem usage before unmounting
ROOT_USAGE=$(df -h "${MOUNT_POINT}" | tail -1 | awk '{print $3}')
log_info "Root filesystem usage: ${ROOT_USAGE}"

# Unmount image
unmount_image "${MOUNT_POINT}" "${LOOP_DEVICE}"

# Shrink image if possible
log_info "Checking if image can be shrunk"
LOOP_DEVICE=$(sudo losetup -f --show "${IMAGE_PATH}")
sudo e2fsck -f "/dev/mapper/$(basename ${LOOP_DEVICE})p2" || true
sudo resize2fs -M "/dev/mapper/$(basename ${LOOP_DEVICE})p2" || true
sudo losetup -d "${LOOP_DEVICE}"

log_info "Stage 3 completed successfully"
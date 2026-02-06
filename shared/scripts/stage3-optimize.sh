#!/bin/bash
set -euo pipefail

# Stage 3: Optimize image
# Clean up and shrink the image

source /scripts/common.sh

# Setup cleanup trap for error handling
trap cleanup_on_exit EXIT ERR INT

WORK_DIR=$1
IMAGE_PATH=$2
MOUNT_POINT="${WORK_DIR}/mount"

log_info "Starting image optimization"

# Mount image
LOOP_DEVICE=$(mount_image "${IMAGE_PATH}" "${MOUNT_POINT}")

# Enable services (without chroot - create symlinks directly)
# This runs after Ansible has installed and configured all services
log_info "Enabling services"

# Core services - always enabled
SERVICES_TO_ENABLE=(
    "ssh"
    "rsyslog"
    "systemd-networkd"
    "systemd-resolved"
    "nftables"
    "zramswap"
    "fake-hwclock"
    "bind9"
    "isc-dhcp-server"
    "hostapd"
    "fail2ban"
    "pimeleon-api"
    "pimeleon-proxy"
    "network-optimization"
    "pim-setup"
)

# Optional services - only enable if configured in profile
# Uses is_service_enabled function from common.sh
if is_service_enabled "dnscrypt_proxy"; then
    SERVICES_TO_ENABLE+=("dnscrypt-proxy")
fi
if is_service_enabled "privoxy"; then
    SERVICES_TO_ENABLE+=("privoxy")
fi
if is_service_enabled "squid"; then
    SERVICES_TO_ENABLE+=("squid")
fi
if is_service_enabled "tor"; then
    SERVICES_TO_ENABLE+=("tor")
fi
if is_service_enabled "pihole"; then
    SERVICES_TO_ENABLE+=("pihole-FTL")
fi

SYSTEMD_DIR="${MOUNT_POINT}/etc/systemd/system"
LIB_SYSTEMD="${MOUNT_POINT}/lib/systemd/system"
MULTI_USER_WANTS="${SYSTEMD_DIR}/multi-user.target.wants"

sudo mkdir -p "${MULTI_USER_WANTS}"

for service in "${SERVICES_TO_ENABLE[@]}"; do
    SERVICE_FILE=""
    if [[ -f "${LIB_SYSTEMD}/${service}.service" ]]; then
        SERVICE_FILE="${LIB_SYSTEMD}/${service}.service"
    elif [[ -f "${SYSTEMD_DIR}/${service}.service" ]]; then
        SERVICE_FILE="${SYSTEMD_DIR}/${service}.service"
    fi

    if [[ -n "${SERVICE_FILE}" ]]; then
        log_info "Enabling service: ${service}"
        # Create symlink using the correct path (convert image path to runtime path)
        RUNTIME_PATH="${SERVICE_FILE#${MOUNT_POINT}}"
        sudo ln -sf "${RUNTIME_PATH}" "${MULTI_USER_WANTS}/${service}.service"
    else
        log_warn "Service not found: ${service}"
    fi
done

# Disable/mask conflicting services
# These services conflict with Pimeleon's AP mode or network management
log_info "Disabling conflicting services"
SERVICES_TO_DISABLE=(
    "wpa_supplicant"      # Conflicts with hostapd AP mode
    "dhcpcd"              # Conflicts with systemd-networkd
    "networking"          # Legacy networking, using systemd-networkd
    "NetworkManager"      # Desktop network manager, not needed
)

for service in "${SERVICES_TO_DISABLE[@]}"; do
    SERVICE_FILE=""
    if [[ -f "${LIB_SYSTEMD}/${service}.service" ]]; then
        SERVICE_FILE="${LIB_SYSTEMD}/${service}.service"
    elif [[ -f "${SYSTEMD_DIR}/${service}.service" ]]; then
        SERVICE_FILE="${SYSTEMD_DIR}/${service}.service"
    fi

    if [[ -n "${SERVICE_FILE}" ]]; then
        log_info "Masking service: ${service}"
        # Mask by linking to /dev/null
        sudo ln -sf /dev/null "${SYSTEMD_DIR}/${service}.service" 2>/dev/null || true
    fi
done

# Setup chroot
setup_chroot "${MOUNT_POINT}"

# Configure APT cache if available
if [[ -n "${APT_CACHE_SERVER:-}" ]]; then
    log_info "Configuring APT cache: ${APT_CACHE_SERVER}:${APT_CACHE_PORT:-3142}"
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
sudo find "${MOUNT_POINT}/var/log" -type f -exec truncate -s 0 {} \; 2>/dev/null || true

# Remove temporary files
log_info "Removing temporary files"
sudo rm -rf "${MOUNT_POINT}/tmp/"* 2>/dev/null || true
sudo rm -rf "${MOUNT_POINT}/var/tmp/"* 2>/dev/null || true
sudo rm -rf "${MOUNT_POINT}/var/cache/apt/archives/"*.deb 2>/dev/null || true
sudo rm -rf "${MOUNT_POINT}/var/lib/apt/lists/"* 2>/dev/null || true

# Remove documentation
log_info "Removing documentation"
sudo rm -rf "${MOUNT_POINT}/usr/share/doc/"* 2>/dev/null || true
sudo rm -rf "${MOUNT_POINT}/usr/share/man/"* 2>/dev/null || true
sudo rm -rf "${MOUNT_POINT}/usr/share/info/"* 2>/dev/null || true
sudo rm -rf "${MOUNT_POINT}/usr/share/lintian/"* 2>/dev/null || true

# Remove locales except supported ones (en, es, ru, uk, zh, ko)
log_info "Removing unused locales"
sudo find "${MOUNT_POINT}/usr/share/locale" -mindepth 1 -maxdepth 1 \
    ! -name 'en*' ! -name 'es*' ! -name 'ru*' ! -name 'uk*' ! -name 'zh*' ! -name 'ko*' \
    -exec rm -rf {} \; 2>/dev/null || true

# Configure locales (en_IE default, plus Spanish, Russian, Ukrainian, Chinese, Korean)
log_info "Configuring locales"
sudo tee "${MOUNT_POINT}/etc/locale.gen" > /dev/null <<EOF
en_IE.UTF-8 UTF-8
en_US.UTF-8 UTF-8
es_ES.UTF-8 UTF-8
ru_RU.UTF-8 UTF-8
uk_UA.UTF-8 UTF-8
zh_CN.UTF-8 UTF-8
ko_KR.UTF-8 UTF-8
EOF
chroot_run "${MOUNT_POINT}" locale-gen
chroot_run "${MOUNT_POINT}" update-locale LANG=en_IE.UTF-8

# Remove SSH host keys (will be regenerated on first boot)
sudo rm -f "${MOUNT_POINT}/etc/ssh/ssh_host_"*

# Create first boot script
log_info "Creating first boot script"
sudo tee "${MOUNT_POINT}/etc/systemd/system/firstboot.service" > /dev/null <<EOF
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

sudo tee "${MOUNT_POINT}/usr/local/bin/firstboot.sh" > /dev/null <<'EOF'
#!/bin/bash
set -e

# Generate SSH host keys if missing
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
fi

# Expand root filesystem to fill SD card
ROOT_PART=$(findmnt -n -o SOURCE /)
ROOT_DEV=$(lsblk -no PKNAME "$ROOT_PART" 2>/dev/null | head -1)
if [ -n "$ROOT_DEV" ]; then
    # Resize partition to fill disk
    echo ", +" | sfdisk -N 2 "/dev/$ROOT_DEV" --no-reread 2>/dev/null || true
    partprobe "/dev/$ROOT_DEV" 2>/dev/null || true
    # Resize filesystem
    resize2fs "$ROOT_PART" 2>/dev/null || true
fi

# Generate machine ID if missing
if [ ! -s /etc/machine-id ]; then
    systemd-machine-id-setup
fi

# Load firewall rules
nft -f /etc/nftables.conf 2>/dev/null || true

echo "First boot setup completed"
EOF

sudo chmod +x "${MOUNT_POINT}/usr/local/bin/firstboot.sh"
chroot_run "${MOUNT_POINT}" systemctl enable firstboot.service

# Zero free space for better compression
log_info "Zeroing free space"
sudo dd if=/dev/zero of="${MOUNT_POINT}/zero.file" bs=1M 2>/dev/null || true
sudo rm -f "${MOUNT_POINT}/zero.file"

# Remove APT cache proxy from final image
if [[ -f "${MOUNT_POINT}/etc/apt/apt.conf.d/01proxy" ]]; then
    log_info "Removing APT cache proxy from final image"
    sudo rm -f "${MOUNT_POINT}/etc/apt/apt.conf.d/01proxy"
fi

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
sudo kpartx -av "${LOOP_DEVICE}"
sleep 2

ROOT_PART="/dev/mapper/$(basename ${LOOP_DEVICE})p2"
if [[ -b "${ROOT_PART}" ]]; then
    log_info "Running filesystem check on root partition"
    sudo e2fsck -f "${ROOT_PART}" || log_warn "e2fsck returned non-zero (may be OK)"
    log_info "Shrinking root filesystem to minimum size"
    sudo resize2fs -M "${ROOT_PART}" || log_warn "resize2fs failed - image not shrunk"
else
    log_warn "Partition mapping not found: ${ROOT_PART} - skipping shrink"
fi

sudo kpartx -d "${LOOP_DEVICE}"
sudo losetup -d "${LOOP_DEVICE}"

log_info "Stage 3 completed successfully"

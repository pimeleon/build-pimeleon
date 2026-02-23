#!/bin/bash
set -euo pipefail

# Stage 3: Optimize image
# Clean up and shrink the image

# shellcheck disable=SC1091
# shellcheck disable=SC1091
source /scripts/common.sh

# Setup cleanup trap for error handling
trap 'cleanup_on_exit' EXIT ERR INT TERM

WORK_DIR=$1
IMAGE_PATH=$2
CLEANUP_IMAGE_PATH="${IMAGE_PATH}"
MOUNT_POINT="${WORK_DIR}/mount"

log_info "Starting image optimization"

# Mount image
mount_image "${IMAGE_PATH}" "${MOUNT_POINT}"
LOOP_DEVICE="${CLEANUP_LOOP_DEVICE}"

# Enable services (without chroot - create symlinks directly)
# This runs after Ansible has installed and configured all services
log_info "Enabling services based on profile configuration"

MULTI_USER_WANTS="${MOUNT_POINT}/etc/systemd/system/multi-user.target.wants"
sudo mkdir -p "${MULTI_USER_WANTS}"

# Map of systemd service name to profile key
# Format: "service_name:profile_key" (profile_key 'none' means always enable)
SERVICES_MAPPING=(
    # Core infrastructure (mostly always enabled)
    "ssh:ssh"
    "systemd-networkd:networkd"
    "nftables:firewall"
    "rsyslog:none"
    "cron:none"
    "fake-hwclock:none"
    "e2scrub_reap:none"
    "unattended-upgrades:none"
    "atd:none"
    "zramswap:zram"
    "dphys-swapfile:swapfile"
    "sysstat:none"
    "smartmontools:none"
    "vnstat:none"
    "atop:none"
    "atopacct:none"
    # Network services
    "hostapd:hostapd"
    "isc-dhcp-server:dhcp_server"
    "named:dns_server"
    "fail2ban:fail2ban"
    "wpa_supplicant:networkd"
    "avahi-daemon:avahi"
    "network-optimization:none"
    # Proxy & Adblock
    "privoxy:privoxy"
    "squid:squid"
    "tor:tor"
    "tor@default:tor"
    "dnscrypt-proxy:dnscrypt_proxy"
    "pihole-FTL:pihole"
    # Pimeleon application
    "pimeleon-api:pi_router_api"
    "pimeleon-proxy:pi_router_api"
    "pim-setup:none"
)

for mapping in "${SERVICES_MAPPING[@]}"; do
    service="${mapping%%:*}"
    profile_key="${mapping#*:}"

    # Check if service should be enabled
    if [[ "$profile_key" != "none" ]]; then
        if ! is_service_enabled "$profile_key"; then
            log_info "Service $service is disabled in profile, skipping."
            continue
        fi
    fi

    SEARCH_NAME="${service}"
    if [[ "${service}" == *"@"* ]]; then
        SEARCH_NAME="${service%%@*}@"
    fi

    log_info "Searching for service: ${service}"

    # Robust discovery: Use find INSIDE the chroot to locate the service unit.
    REL_SERVICE_PATH=$(chroot_run "${MOUNT_POINT}" find /lib/systemd/system /usr/lib/systemd/system /etc/systemd/system -name "${SEARCH_NAME}.service" -print -quit 2>/dev/null || true)

    if [[ -n "${REL_SERVICE_PATH}" ]]; then
        log_info "Enabling service: ${service} (found at ${REL_SERVICE_PATH})"
        # Create symlink relative to the image's filesystem in multi-user.target.wants
        sudo ln -sf "${REL_SERVICE_PATH}" "${MULTI_USER_WANTS}/${service}.service"

        # Special handling for template instances (e.g., tor@default)
        if [[ "${service}" == *"@"* ]]; then
            master_service="${service%%@*}"
            instance_name="${service#*@}"
            wants_dir="${MOUNT_POINT}/etc/systemd/system/${master_service}.service.wants"
            log_info "Creating template instance symlink for ${service} in ${wants_dir}"
            sudo mkdir -p "${wants_dir}"
            sudo ln -sf "${REL_SERVICE_PATH}" "${wants_dir}/${instance_name}.service"
        fi
    else
        # Fallback/Diagnostic for legacy Pi-hole or specific cases
        if [[ "${service}" == "pihole-FTL" ]] || [[ "${service}" == "isc-dhcp-server" ]] || [[ "${service}" == "pim-setup" ]]; then
             log_info "Attempting legacy service enablement for ${service}..."
             chroot_run "${MOUNT_POINT}" systemctl enable "${service}" 2>/dev/null || true
        else
             # CRITICAL: Missing service that is supposed to be enabled is a fatal error
             log_error "FATAL: Service not found: ${service}. (Checked standard systemd paths in chroot)"
             if [[ "${DEBUG:-0}" == "1" ]]; then
                 log_info "DEBUG: Listing all service files in chroot for diagnostics:"
                 chroot_run "${MOUNT_POINT}" find /lib/systemd/system /usr/lib/systemd/system /etc/systemd/system -name "*.service" | grep "${SEARCH_NAME}" || true
             fi
             die "Build failed: Required service '${service}' not found in image."
        fi
    fi
done

# Setup chroot
setup_chroot "${MOUNT_POINT}"

# Configure APT cache if available
configure_chroot_apt_proxy "${MOUNT_POINT}"

# Consolidated Image Cleanup
log_info "Performing final image cleanup and optimization"

# Remove multimedia-related packages and directories (use -qq for quiet output)
log_info "Purging multimedia components"
chroot_run "${MOUNT_POINT}" apt-get purge -y -qq \
    alsa-utils alsa-base libasound2 \
    bluez pi-bluetooth || true
safe_rm "${MOUNT_POINT}/usr/share/alsa"
safe_rm "${MOUNT_POINT}/var/lib/alsa"

# Remove unnecessary packages to reduce image size
log_info "Removing unnecessary packages"
chroot_run "${MOUNT_POINT}" apt-get purge -y -qq \
    man-db manpages info install-info \
    tasksel tasksel-data || true

# Clean package manager artifacts
log_info "Cleaning package cache"
chroot_run "${MOUNT_POINT}" apt-get clean
chroot_run "${MOUNT_POINT}" apt-get autoclean
chroot_run "${MOUNT_POINT}" apt-get autoremove -y -qq

# Clear logs and temporary files
log_info "Clearing logs and temporary files"
sudo find "${MOUNT_POINT}/var/log" -type f -exec truncate -s 0 {} \; 2>/dev/null || true
safe_rm "${MOUNT_POINT}/tmp/*"
safe_rm "${MOUNT_POINT}/var/tmp/*"
safe_rm "${MOUNT_POINT}/var/cache/apt/archives/*.deb"
safe_rm "${MOUNT_POINT}/var/lib/apt/lists/*"

# Remove swap file created during build (will be recreated on first boot if needed)
safe_rm "${MOUNT_POINT}/swap"

# Remove documentation and localizations
log_info "Removing documentation and unused locales"
safe_rm "${MOUNT_POINT}/usr/share/doc/*"
safe_rm "${MOUNT_POINT}/usr/share/man/*"
safe_rm "${MOUNT_POINT}/usr/share/info/*"
safe_rm "${MOUNT_POINT}/usr/share/lintian/*"

# Remove unused locales except supported ones
sudo find "${MOUNT_POINT}/usr/share/locale" -mindepth 1 -maxdepth 1 \
    ! -name 'en*' ! -name 'es*' ! -name 'ru*' ! -name 'uk*' ! -name 'zh*' ! -name 'ko*' \
    -exec rm -rf {} \; 2>/dev/null || true

# Remove SSH host keys (will be regenerated on first boot)
safe_rm "${MOUNT_POINT}/etc/ssh/ssh_host_*"

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

# Clean up /etc/hosts from build-time artifacts (Docker hostnames, GitHub IPs)
log_info "Restoring clean /etc/hosts"
sudo tee "${MOUNT_POINT}/etc/hosts" > /dev/null <<EOF
127.0.0.1	localhost
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters

127.0.1.1 pimeleon
EOF

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
safe_rm "${MOUNT_POINT}/zero.file"

# Remove APT cache proxy from final image
remove_chroot_apt_proxy "${MOUNT_POINT}"

# Cleanup chroot
cleanup_chroot "${MOUNT_POINT}"

# Get filesystem usage before unmounting
ROOT_USAGE=$(df -h "${MOUNT_POINT}" | tail -1 | awk '{print $3}')
log_info "Root filesystem usage: ${ROOT_USAGE}"

# Verify stage completion
verify_stage 3 "${MOUNT_POINT}"

# Ensure boot is unmounted if still there (sometimes happens after chroot)
if mountpoint -q "${MOUNT_POINT}/boot" 2>/dev/null; then
    sudo umount "${MOUNT_POINT}/boot" || sudo umount -l "${MOUNT_POINT}/boot" || true
fi

# Unmount image
unmount_image "${MOUNT_POINT}" "${LOOP_DEVICE}"

# Shrink image if possible
log_info "Checking if image can be shrunk"
# Use a subshell to ensure cleanup of loop device even if commands fail
(
    LOOP_DEV=$(sudo losetup -f --show "${IMAGE_PATH}")
    # Setup trap for inner loop device
    trap 'sudo kpartx -d "${LOOP_DEV}" 2>/dev/null || true; sudo losetup -d "${LOOP_DEV}" 2>/dev/null || true' EXIT

    sudo kpartx -av "${LOOP_DEV}" > /dev/null
    sleep 2

    ROOT_PART="/dev/mapper/$(basename "${LOOP_DEV}")p2"
    if [[ -b "${ROOT_PART}" ]]; then
        log_info "Running filesystem check on root partition: ${ROOT_PART}"
        # -f: force check even if clean
        # -y: assume yes to all questions (required for non-interactive)
        sudo e2fsck -fy "${ROOT_PART}" || log_warn "e2fsck returned non-zero (may be OK)"

        log_info "Shrinking root filesystem to minimum size"
        # Get minimum size for informational purposes
        MIN_SIZE=$(sudo resize2fs -P "${ROOT_PART}" 2>/dev/null | cut -d: -f2 | xargs || echo "unknown")
        log_info "Estimated minimum size in blocks: ${MIN_SIZE}"

        if sudo resize2fs -M "${ROOT_PART}"; then
            log_info "Filesystem shrunk successfully"
        else
            log_warn "resize2fs failed - image not shrunk"
        fi

        log_info "Final filesystem check and repair"
        sudo e2fsck -fy "${ROOT_PART}" || log_warn "Final e2fsck returned non-zero (may be OK)"
    else
        log_warn "Partition mapping not found: ${ROOT_PART} - skipping shrink"
        log_info "Available mappings:"
        ls -la /dev/mapper/ || true
    fi
)

log_info "Stage 3 completed successfully"

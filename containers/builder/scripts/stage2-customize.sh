#!/bin/bash
set -euo pipefail

# Stage 2: Customize system
# Install packages and apply configurations

source /scripts/common.sh

WORK_DIR=$1
IMAGE_PATH=$2
MOUNT_POINT="${WORK_DIR}/mount"
BOOT_MOUNT="${WORK_DIR}/boot"

log_info "Starting system customization"

# Mount image
LOOP_DEVICE=$(mount_image "${IMAGE_PATH}" "${MOUNT_POINT}")

# Boot partition is already mounted at ${MOUNT_POINT}/boot by mount_image function
BOOT_MOUNT="${MOUNT_POINT}/boot"

# Setup chroot
setup_chroot "${MOUNT_POINT}"

# Configure APT cache for chroot environment early
if [[ -n "${APT_CACHE_SERVER:-}" ]]; then
    log_info "Configuring APT cache for chroot environment"
    sudo mkdir -p "${MOUNT_POINT}/etc/apt/apt.conf.d"
    sudo tee "${MOUNT_POINT}/etc/apt/apt.conf.d/01proxy" > /dev/null <<EOF
# APT Cache Configuration for Build Process
Acquire::http::Proxy "http://${APT_CACHE_SERVER}:${APT_CACHE_PORT:-3142}";
Acquire::https::Proxy "DIRECT";
EOF
fi

# Update package lists
log_info "Updating package lists"
chroot_run "${MOUNT_POINT}" apt-get update

# Install essential packages only (systemd-resolved is part of systemd package)
log_info "Installing essential packages"
chroot_run "${MOUNT_POINT}" apt-get install -y --no-install-recommends \
    systemd \
    systemd-sysv \
    udev \
    dbus \
    sudo \
    openssh-server \
    wget \
    curl \
    ca-certificates \
    net-tools \
    iproute2 \
    iptables \
    wireless-tools \
    firmware-brcm80211 \
    rsyslog

# Install Pi-specific packages (kernel, bootloader, firmware)
log_info "Installing Raspberry Pi kernel and firmware"
chroot_run "${MOUNT_POINT}" apt-get install -y --no-install-recommends \
    raspberrypi-kernel \
    libraspberrypi-bin

# Copy Pi boot firmware to boot partition
log_info "Copying Pi boot firmware to boot partition"
if [[ -d "${MOUNT_POINT}/boot" ]]; then
    # Pi boot files are installed to /boot by raspberrypi-kernel package
    # Copy essential boot files to FAT32 boot partition
    sudo cp "${MOUNT_POINT}/boot/bootcode.bin" "${BOOT_MOUNT}/" || log_warn "bootcode.bin not found"
    sudo cp "${MOUNT_POINT}/boot/start*.elf" "${BOOT_MOUNT}/" || log_warn "start.elf files not found"  
    sudo cp "${MOUNT_POINT}/boot/fixup*.dat" "${BOOT_MOUNT}/" || log_warn "fixup.dat files not found"
    sudo cp "${MOUNT_POINT}/boot/kernel*.img" "${BOOT_MOUNT}/" || log_warn "kernel images not found"
    sudo cp "${MOUNT_POINT}/boot/bcm2710-rpi-3-b-plus.dtb" "${BOOT_MOUNT}/" || log_warn "Pi 3B+ device tree not found"
    sudo cp -r "${MOUNT_POINT}/boot/overlays" "${BOOT_MOUNT}/" 2>/dev/null || log_warn "Boot overlays not found"
else
    log_warn "Pi firmware not found in expected location"
fi

# Install basic networking tools
log_info "Installing basic networking tools"
chroot_run "${MOUNT_POINT}" apt-get install -y --no-install-recommends \
    bridge-utils \
    dnsmasq \
    hostapd \
    wpasupplicant

# Configure system
log_info "Configuring system"

# Enable IP forwarding
sudo mkdir -p "${MOUNT_POINT}/etc/sysctl.d"
sudo tee "${MOUNT_POINT}/etc/sysctl.d/30-ip-forward.conf" > /dev/null <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.all.log_martians=1
net.ipv4.tcp_syncookies=1
net.ipv4.icmp_echo_ignore_broadcasts=1
EOF
# sudo cp /tmp/sysctl-config "${MOUNT_POINT}/etc/sysctl.d/30-ip-forward.conf"
sudo chmod 644 "${MOUNT_POINT}/etc/sysctl.d/30-ip-forward.conf"

# Configure systemd-networkd
sudo mkdir -p "${MOUNT_POINT}/etc/systemd/network"
sudo chmod 755 "${MOUNT_POINT}/etc/systemd/network"

# Configure eth0 for DHCP (WAN)
cat > /tmp/eth0-network <<EOF
[Match]
Name=eth0

[Network]
DHCP=yes
EOF
sudo cp /tmp/eth0-network "${MOUNT_POINT}/etc/systemd/network/10-eth0.network"
sudo chmod 644 "${MOUNT_POINT}/etc/systemd/network/10-eth0.network"

# Configure management interface on eth0:1
cat > /tmp/eth0-mgmt <<EOF
[Match]
Name=eth0

[Address]
Address=172.16.0.1/24
EOF
sudo cp /tmp/eth0-mgmt "${MOUNT_POINT}/etc/systemd/network/20-eth0-mgmt.network"
sudo chmod 644 "${MOUNT_POINT}/etc/systemd/network/20-eth0-mgmt.network"

# Configure SSH
sudo sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' "${MOUNT_POINT}/etc/ssh/sshd_config"
sudo sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' "${MOUNT_POINT}/etc/ssh/sshd_config"
echo "AllowUsers pi" | sudo tee -a "${MOUNT_POINT}/etc/ssh/sshd_config" > /dev/null

# Create Pi-specific groups first
log_info "Creating Pi-specific groups"
for group in gpio i2c spi; do
    chroot_run "${MOUNT_POINT}" groupadd -f -r "$group" || true
done

# Create pi user
log_info "Creating pi user"
chroot_run "${MOUNT_POINT}" useradd -m -s /bin/bash -G sudo,adm,dialout,cdrom,audio,video,plugdev,games,users,input,netdev,gpio,i2c,spi pi
# Set password - use environment variable or default thematic word
TEMP_PASSWORD="${PI_INITIAL_PASSWORD:-netblox}"
echo "pi:${TEMP_PASSWORD}" | chroot_run "${MOUNT_POINT}" chpasswd
echo "${TEMP_PASSWORD}" | sudo tee "${OUTPUT_DIR}/pi-initial-password.txt" > /dev/null
sudo chmod 600 "${OUTPUT_DIR}/pi-initial-password.txt"
log_warn "Initial password saved to: ${OUTPUT_DIR}/pi-initial-password.txt"

# Create restricted sudo access for pi user
sudo mkdir -p "${MOUNT_POINT}/etc/sudoers.d"
sudo chmod 777 "${MOUNT_POINT}/etc/sudoers.d"
cat > /tmp/sudoers-pi << EOF
pi ALL=(ALL) PASSWD: /sbin/reboot, /sbin/poweroff, /usr/bin/systemctl
EOF
sudo cp /tmp/sudoers-pi "${MOUNT_POINT}/etc/sudoers.d/010_pi-restricted"
sudo chmod 777 "${MOUNT_POINT}/etc/sudoers.d/010_pi-restricted"

# Configure basic services (systemd-resolved service is part of systemd package)
log_info "Configuring services"
chroot_run "${MOUNT_POINT}" systemctl enable ssh
chroot_run "${MOUNT_POINT}" systemctl enable rsyslog
chroot_run "${MOUNT_POINT}" systemctl enable systemd-networkd
chroot_run "${MOUNT_POINT}" systemctl enable systemd-resolved

# Apply Ansible playbooks if available
if [[ -d "${ANSIBLE_DIR}/playbooks" ]] && [[ -n "$(ls -A ${ANSIBLE_DIR}/playbooks/*.yml 2>/dev/null)" ]]; then
    log_info "Applying Ansible playbooks"
    export ANSIBLE_HOST_KEY_CHECKING=False
    
    # Create temporary inventory
    cat > "${WORK_DIR}/inventory" <<EOF
[pimeleon]
${MOUNT_POINT} ansible_connection=chroot
EOF
    
    # Run playbooks
    for playbook in ${ANSIBLE_DIR}/playbooks/*.yml; do
        log_info "Running playbook: $(basename $playbook)"
        ansible-playbook -i "${WORK_DIR}/inventory" "$playbook" || log_warn "Playbook failed: $playbook"
    done
fi

# Copy custom configs if available
if [[ -d "${CONFIG_DIR}" ]]; then
    log_info "Copying custom configurations"
    
    # Network configs
    if [[ -d "${CONFIG_DIR}/network" ]] && [[ -n "$(ls -A ${CONFIG_DIR}/network/* 2>/dev/null)" ]]; then
        sudo cp -r "${CONFIG_DIR}/network/"* "${MOUNT_POINT}/etc/network/" || true
    fi
    
    # Security configs
    if [[ -d "${CONFIG_DIR}/security" ]] && [[ -n "$(ls -A ${CONFIG_DIR}/security/* 2>/dev/null)" ]]; then
        sudo cp -r "${CONFIG_DIR}/security/"* "${MOUNT_POINT}/etc/" || true
    fi
    
    # Service configs
    if [[ -d "${CONFIG_DIR}/services" ]] && [[ -n "$(ls -A ${CONFIG_DIR}/services/* 2>/dev/null)" ]]; then
        sudo cp -r "${CONFIG_DIR}/services/"* "${MOUNT_POINT}/etc/" || true
    fi
fi

# Clean up APT cache configuration from final image
if [[ -f "${MOUNT_POINT}/etc/apt/apt.conf.d/01proxy" ]]; then
    log_info "Removing APT cache configuration from final image"
    sudo rm -f "${MOUNT_POINT}/etc/apt/apt.conf.d/01proxy"
fi

# Cleanup chroot
cleanup_chroot "${MOUNT_POINT}"

# Unmount image (includes boot partition)
unmount_image "${MOUNT_POINT}" "${LOOP_DEVICE}"

log_info "Stage 2 completed successfully"
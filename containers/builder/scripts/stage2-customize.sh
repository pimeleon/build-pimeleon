#!/bin/bash
set -euo pipefail

# Stage 2: Customize system
# Install packages and apply configurations

source /scripts/common.sh

WORK_DIR=$1
IMAGE_PATH=$2
MOUNT_POINT="${WORK_DIR}/mount"

log_info "Starting system customization"

# Mount image
LOOP_DEVICE=$(mount_image "${IMAGE_PATH}" "${MOUNT_POINT}")

# Setup chroot
setup_chroot "${MOUNT_POINT}"

# Update package lists
log_info "Updating package lists"
chroot_run "${MOUNT_POINT}" apt-get update

# Install essential packages
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
    gnupg \
    lsb-release \
    net-tools \
    iproute2 \
    iptables \
    ipset \
    dnsmasq \
    hostapd \
    bridge-utils \
    vlan \
    wireless-tools \
    wpasupplicant \
    rfkill \
    crda \
    firmware-brcm80211 \
    raspberrypi-net-mods

# Install routing and firewall packages
log_info "Installing routing packages"
chroot_run "${MOUNT_POINT}" apt-get install -y --no-install-recommends \
    nftables \
    conntrack \
    conntrackd \
    keepalived \
    bird2 \
    frr \
    strongswan \
    openvpn \
    wireguard-tools

# Install monitoring and management tools
log_info "Installing monitoring tools"
chroot_run "${MOUNT_POINT}" apt-get install -y --no-install-recommends \
    htop \
    iotop \
    nethogs \
    vnstat \
    fail2ban \
    rsyslog \
    logrotate \
    monit \
    prometheus-node-exporter

# Configure system
log_info "Configuring system"

# Enable IP forwarding
cat > "${MOUNT_POINT}/etc/sysctl.d/30-ip-forward.conf" <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.all.log_martians=1
net.ipv4.tcp_syncookies=1
net.ipv4.icmp_echo_ignore_broadcasts=1
EOF

# Configure network interfaces
cat > "${MOUNT_POINT}/etc/network/interfaces" <<EOF
# Loopback
auto lo
iface lo inet loopback

# Ethernet WAN
auto eth0
iface eth0 inet dhcp

# Management interface
auto eth0:1
iface eth0:1 inet static
    address 172.16.0.1
    netmask 255.255.255.0
EOF

# Configure SSH
sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' "${MOUNT_POINT}/etc/ssh/sshd_config"
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' "${MOUNT_POINT}/etc/ssh/sshd_config"
echo "AllowUsers pi" >> "${MOUNT_POINT}/etc/ssh/sshd_config"

# Create pi user
log_info "Creating pi user"
chroot_run "${MOUNT_POINT}" useradd -m -s /bin/bash -G sudo,adm,dialout,cdrom,audio,video,plugdev,games,users,input,netdev,gpio,i2c,spi pi
echo "pi:raspberry" | chroot_run "${MOUNT_POINT}" chpasswd
echo "pi ALL=(ALL) NOPASSWD: ALL" > "${MOUNT_POINT}/etc/sudoers.d/010_pi-nopasswd"

# Configure services
log_info "Configuring services"
chroot_run "${MOUNT_POINT}" systemctl enable ssh
chroot_run "${MOUNT_POINT}" systemctl enable systemd-networkd
chroot_run "${MOUNT_POINT}" systemctl enable systemd-resolved
chroot_run "${MOUNT_POINT}" systemctl enable nftables
chroot_run "${MOUNT_POINT}" systemctl enable fail2ban

# Apply Ansible playbooks if available
if [[ -d "${ANSIBLE_DIR}/playbooks" ]] && [[ -n "$(ls -A ${ANSIBLE_DIR}/playbooks/*.yml 2>/dev/null)" ]]; then
    log_info "Applying Ansible playbooks"
    export ANSIBLE_HOST_KEY_CHECKING=False
    
    # Create temporary inventory
    cat > "${WORK_DIR}/inventory" <<EOF
[pi_router]
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

# Cleanup chroot
cleanup_chroot "${MOUNT_POINT}"

# Unmount image
unmount_image "${MOUNT_POINT}" "${LOOP_DEVICE}"

log_info "Stage 2 completed successfully"
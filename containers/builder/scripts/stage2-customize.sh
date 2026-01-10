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

# Install essential packages (systemd-resolved is separate package in Bookworm+)
log_info "Installing essential packages"
chroot_run "${MOUNT_POINT}" apt-get install -y --no-install-recommends \
    systemd \
    systemd-sysv \
    systemd-resolved \
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

# Verify Pi boot firmware was installed to boot partition
# Note: raspberrypi-kernel installs files directly to /boot (mounted FAT32 partition)
log_info "Verifying Pi boot firmware installation"
FIRMWARE_OK=true
[[ -f "${BOOT_MOUNT}/bootcode.bin" ]] || { log_warn "bootcode.bin not found"; FIRMWARE_OK=false; }
[[ -f "${BOOT_MOUNT}/start.elf" ]] || { log_warn "start.elf not found"; FIRMWARE_OK=false; }
[[ -f "${BOOT_MOUNT}/fixup.dat" ]] || { log_warn "fixup.dat not found"; FIRMWARE_OK=false; }
[[ -f "${BOOT_MOUNT}/kernel7.img" ]] || { log_warn "kernel7.img not found"; FIRMWARE_OK=false; }
[[ -f "${BOOT_MOUNT}/bcm2710-rpi-3-b-plus.dtb" ]] || { log_warn "Pi 3B+ device tree not found"; FIRMWARE_OK=false; }
[[ -d "${BOOT_MOUNT}/overlays" ]] || { log_warn "Boot overlays not found"; FIRMWARE_OK=false; }
if [[ "$FIRMWARE_OK" == "true" ]]; then
    log_info "All Pi boot firmware files verified"
else
    log_warn "Some firmware files missing - image may not boot"
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
TEMP_PASSWORD="${PIMELEON_INITIAL_PASSWORD:-netblox}"
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

    # Determine platform group from environment (3B+ -> raspberrypi_3bplus, 4B -> raspberrypi_4b)
    PLATFORM_GROUP="raspberrypi_$(echo ${PIMELEON_RPI_MODEL:-3B+} | tr '[:upper:]' '[:lower:]' | tr -d '+')"
    log_info "Platform group: ${PLATFORM_GROUP}"

    # Create temporary inventory with platform group membership
    cat > "${WORK_DIR}/inventory" <<EOF
[all]
pimeleon ansible_connection=chroot ansible_host=${MOUNT_POINT}

[raspberrypi]
pimeleon

[${PLATFORM_GROUP}]
pimeleon

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOF

    # Copy group_vars to work directory for ansible to find
    if [[ -d "${ANSIBLE_DIR}/inventory/group_vars" ]]; then
        mkdir -p "${WORK_DIR}/group_vars"
        cp -r "${ANSIBLE_DIR}/inventory/group_vars/"* "${WORK_DIR}/group_vars/"
    fi

    # Copy profile vars to work directory
    if [[ -f "${ANSIBLE_DIR}/inventory/group_vars/all/profiles/${PIMELEON_PROFILE:-development}.yml" ]]; then
        cp "${ANSIBLE_DIR}/inventory/group_vars/all/profiles/${PIMELEON_PROFILE:-development}.yml" "${WORK_DIR}/group_vars/all/profile.yml"
        log_info "Using profile: ${PIMELEON_PROFILE:-development}"
    fi

    # Run playbooks with platform, version, and profile extra-vars
    for playbook in ${ANSIBLE_DIR}/playbooks/*.yml; do
        log_info "Running playbook: $(basename $playbook)"
        ansible-playbook \
            -i "${WORK_DIR}/inventory" \
            --extra-vars "platform_model=${PIMELEON_RPI_MODEL:-3B+}" \
            --extra-vars "debian_version=${RASPBIAN_VERSION:-bullseye}" \
            --extra-vars "pimeleon_profile=${PIMELEON_PROFILE:-development}" \
            --extra-vars "pimeleon_initial_password=${PIMELEON_INITIAL_PASSWORD:-netblox}" \
            "$playbook" || die "Playbook failed: $playbook"
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

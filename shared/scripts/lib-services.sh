#!/bin/bash
# Library for service installation functions

# Install hostapd (always use apt for stability and speed)
install_hostapd() {
    local mount_point=$1
    if is_service_enabled "hostapd" 2>/dev/null; then
        log_info "Installing hostapd from APT"
        chroot_run "${mount_point}" bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get install -qy --no-install-recommends hostapd"
        # Create compatibility symlink for systemd service (pointing to standard location)
        chroot_run "${mount_point}" ln -sf /usr/sbin/hostapd /usr/local/bin/hostapd
    else
        log_info "hostapd not enabled in profile, skipping installation"
    fi
}

# Install Pi-hole (always use official installer - uses pre-built binaries)
install_pihole() {
    local mount_point=$1
    if is_service_enabled "pihole" 2>/dev/null; then
        log_info "Installing Pi-hole using official installer"

        # Pre-seed configuration for unattended install
        sudo mkdir -p "${mount_point}/etc/pihole"
        sudo tee "${mount_point}/etc/pihole/setupVars.conf" > /dev/null <<EOF
PIHOLE_INTERFACE=wlan0
PIHOLE_DNS_1=127.0.0.1#5054
INSTALL_WEB_INTERFACE=false
INSTALL_WEB_SERVER=false
LIGHTTPD_ENABLED=false
QUERY_LOGGING=false
INSTALL_FTL=true
EOF
        # Pre-seed pihole.toml (v6) to provide paths for gravity.sh
        sudo tee "${mount_point}/etc/pihole/pihole.toml" > /dev/null <<EOF
[files]
  log.dnsmasq = "/var/log/pihole/pihole.log"
  log.ftl = "/var/log/pihole/FTL.log"
  database = "/etc/pihole/pihole-FTL.db"
  gravity = "/etc/pihole/gravity.db"
EOF
        # CHROOT-SAFE WORKAROUND:
        # 1. Create pihole user/group early
        chroot_run "${mount_point}" groupadd -f -r pihole
        chroot_run "${mount_point}" useradd -r -s /usr/sbin/nologin -g pihole -d /etc/pihole pihole || true

        # 2. Mock pihole-FTL to bypass installer service checks
        # Mock in /usr/bin where the service expects it
        sudo mkdir -p "${mount_point}/usr/bin"
        sudo ln -sf /bin/true "${mount_point}/usr/bin/pihole-FTL"
        sudo ln -sf /bin/true "${mount_point}/usr/bin/pihole"

        # 3. Download and run installer
        log_info "Downloading Pi-hole installer..."
        wget -qO /tmp/basic-install.sh https://install.pi-hole.net
        sudo cp /tmp/basic-install.sh "${mount_point}/tmp/basic-install.sh"
        sudo chmod +x "${mount_point}/tmp/basic-install.sh"

        # 4. Pre-seed pihole.toml (v6) to provide paths for gravity.sh
        sudo mkdir -p "${mount_point}/etc/pihole"
        sudo tee "${mount_point}/etc/pihole/pihole.toml" > /dev/null <<EOF
[files]
  log.dnsmasq = "/var/log/pihole/pihole.log"
  log.ftl = "/var/log/pihole/FTL.log"
  database = "/etc/pihole/pihole-FTL.db"
  gravity = "/etc/pihole/gravity.db"
  gravity_tmp = "/tmp"
EOF
        sudo chown -R 999:999 "${mount_point}/etc/pihole" # Ensure pihole user can read it

        log_info "Running Pi-hole installer inside chroot..."
        sudo chattr +i "${mount_point}/etc/resolv.conf" 2>/dev/null || true
        chroot_run "${mount_point}" bash -c "export PIHOLE_SKIP_OS_CHECK=true; bash /tmp/basic-install.sh --unattended" || {
            sudo chattr -i "${mount_point}/etc/resolv.conf" 2>/dev/null || true
            die "Pi-hole installer failed."
        }
        sudo chattr -i "${mount_point}/etc/resolv.conf" 2>/dev/null || true

        # Cleanup mocks
        if [[ -L "${mount_point}/usr/bin/pihole-FTL" ]] && [[ $(readlink "${mount_point}/usr/bin/pihole-FTL") == "/bin/true" ]]; then
            sudo rm -f "${mount_point}/usr/bin/pihole-FTL"
            if [[ -f "${mount_point}/usr/local/bin/pihole-FTL" ]]; then
                sudo mv "${mount_point}/usr/local/bin/pihole-FTL" "${mount_point}/usr/bin/pihole-FTL"
            fi
        fi
        if [[ -L "${mount_point}/usr/bin/pihole" ]] && [[ $(readlink "${mount_point}/usr/bin/pihole") == "/bin/true" ]]; then
            sudo rm -f "${mount_point}/usr/bin/pihole"
            if [[ -f "${mount_point}/usr/local/bin/pihole" ]]; then
                sudo mv "${mount_point}/usr/local/bin/pihole" "${mount_point}/usr/bin/pihole"
            fi
        fi

        # RESTORE DNS
        sudo rm -f "${mount_point}/etc/resolv.conf"
        sudo tee "${mount_point}/etc/resolv.conf" > /dev/null <<EOF
# DNS for chroot build environment
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
        safe_rm "${mount_point}/tmp/basic-install.sh"
    else
        log_info "Pi-hole not enabled in profile, skipping installation"
    fi
}

# Install Tor (source or apt)
install_tor() {
    local mount_point=$1
    if is_service_enabled "tor" 2>/dev/null; then
        if is_build_from_source_enabled "tor" 2>/dev/null; then
            log_info "Building Tor from source (Production mode)"
            local tor_version_val
            local ansible_dir="${ANSIBLE_DIR:-/ansible}"
            tor_version_val=$(grep "tor:" "${ansible_dir}/vars/common/versions.yml" | head -1 | awk '{print $2}' | tr -d '"')
            sudo cp /scripts/build-tor.sh "${mount_point}/tmp/build-tor.sh"
            sudo chmod +x "${mount_point}/tmp/build-tor.sh"
            chroot_run "${mount_point}" /tmp/build-tor.sh "${tor_version_val:-0.4.8.13}"
            if [[ -x "${mount_point}/usr/local/bin/tor" ]]; then
                log_info "Tor compiled and installed successfully"
                chroot_run "${mount_point}" /usr/local/bin/tor --version | head -1
            else
                die "Tor compilation failed - binary not found"
            fi
            safe_rm "${mount_point}/tmp/build-tor.sh"
        else
            log_info "Installing Tor from APT (Development mode)"
            chroot_run "${mount_point}" bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get install -qy --no-install-recommends tor tor-geoipdb"
        fi
    else
        log_info "Tor not enabled in profile, skipping installation"
    fi
}

# Install dnscrypt-proxy (source or apt)
install_dnscrypt_proxy() {
    local mount_point=$1
    if is_service_enabled "dnscrypt_proxy" 2>/dev/null; then
        if [[ "${PIMELEON_PROFILE:-}" == "production" ]]; then
            log_info "Building dnscrypt-proxy from source (Production mode)"
            local dnscrypt_version_val
            local ansible_dir="${ANSIBLE_DIR:-/ansible}"
            dnscrypt_version_val=$(grep "dnscrypt_proxy:" "${ansible_dir}/vars/common/versions.yml" | head -1 | awk '{print $2}' | tr -d '"')
            sudo cp /scripts/build-dnscrypt-proxy.sh "${mount_point}/tmp/build-dnscrypt-proxy.sh"
            sudo chmod +x "${mount_point}/tmp/build-dnscrypt-proxy.sh"
            chroot_run "${mount_point}" /tmp/build-dnscrypt-proxy.sh "${dnscrypt_version_val:-2.1.5}"
            if [[ -x "${mount_point}/usr/local/bin/dnscrypt-proxy" ]]; then
                log_info "dnscrypt-proxy compiled and installed successfully"
                chroot_run "${mount_point}" /usr/local/bin/dnscrypt-proxy -version
            else
                die "dnscrypt-proxy compilation failed - binary not found"
            fi
            safe_rm "${mount_point}/tmp/build-dnscrypt-proxy.sh"
        else
            log_info "Installing dnscrypt-proxy from APT (Development mode)"
            chroot_run "${mount_point}" bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get install -qy --no-install-recommends dnscrypt-proxy"
        fi
    else
        log_info "dnscrypt-proxy not enabled in profile, skipping installation"
    fi
}

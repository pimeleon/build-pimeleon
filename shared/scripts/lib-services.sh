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
        die "hostapd is not enabled in profile — cannot build Pimeleon image without it"
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
        die "pihole is not enabled in profile — cannot build Pimeleon image without it"
    fi
}

# Install Tor (always use apt)
install_tor() {
    local mount_point=$1
    if is_service_enabled "tor" 2>/dev/null; then
        log_info "Installing Tor from APT"
        chroot_run "${mount_point}" bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get install -qy --no-install-recommends tor tor-geoipdb"
    else
        die "tor is not enabled in profile — cannot build Pimeleon image without it"
    fi
}

# Install dnscrypt-proxy (artifact or APT)
install_dnscrypt_proxy() {
    local mount_point=$1
    if is_service_enabled "dnscrypt_proxy" 2>/dev/null; then
        # 1. Try to fetch pre-built artifact (local cache or registry)
        sudo mkdir -p "${DOWNLOAD_DIR}"
        if get_pimeleon_apps_artifact "dnscrypt-proxy" "${RPI_ARCH:-armhf}" "${DOWNLOAD_DIR}"; then
            log_info "Installing dnscrypt-proxy from artifact"
            sudo tar -xzf "${DOWNLOAD_DIR}/dnscrypt-proxy.tar.gz" -C "${mount_point}/"
            return
        fi

        die "Failed to fetch dnscrypt-proxy artifact — cannot continue"
    else
        die "dnscrypt-proxy is not enabled in profile — cannot build Pimeleon image without it"
    fi
}

# Install wpa_supplicant (artifact only)
# Always installed regardless of service enablement — binary is required even when
# wpa_supplicant.service is disabled (AP mode: hostapd owns wlan0, service must not run)
install_wpasupplicant() {
    local mount_point=$1
    sudo mkdir -p "${DOWNLOAD_DIR}"
    if get_pimeleon_apps_artifact "wpa_supplicant" "${RPI_ARCH:-armhf}" "${DOWNLOAD_DIR}"; then
        log_info "Installing wpa_supplicant from artifact"
        sudo tar -xzf "${DOWNLOAD_DIR}/wpa_supplicant.tar.gz" -C "${mount_point}/"
        return
    fi

    die "Failed to fetch wpa_supplicant artifact — cannot continue"
}

# Install privoxy (artifact only)
install_privoxy() {
    local mount_point=$1
    if is_service_enabled "privoxy" 2>/dev/null; then
        sudo mkdir -p "${DOWNLOAD_DIR}"
        if get_pimeleon_apps_artifact "privoxy" "${RPI_ARCH:-armhf}" "${DOWNLOAD_DIR}"; then
            log_info "Installing privoxy from artifact"
            sudo tar -xzf "${DOWNLOAD_DIR}/privoxy.tar.gz" -C "${mount_point}/"
            return
        fi

        die "Failed to fetch privoxy artifact — cannot continue"
    else
        die "privoxy is not enabled in profile — cannot build Pimeleon image without it"
    fi
}

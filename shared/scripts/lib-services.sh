#!/bin/bash
# Library for service installation functions

# Install hostapd (source or apt)
install_hostapd() {
    local mount_point=$1
    if is_service_enabled "hostapd" 2>/dev/null; then
        if is_build_from_source_enabled "hostapd" 2>/dev/null; then
            log_info "Building hostapd from source with WPA3/SAE support (Production mode)"
            local hostapd_version="hostap_2_10"
            local hostapd_build_dir="${mount_point}/tmp/hostapd-build"

            sudo mkdir -p "${hostapd_build_dir}"
            if [[ ! -d "${hostapd_build_dir}/hostap" ]]; then
                log_info "Cloning hostap repository (${hostapd_version})..."
                sudo git clone --depth 1 --branch "${hostapd_version}" \
                    https://git.w1.fi/hostap.git "${hostapd_build_dir}/hostap"
            fi

            sudo cp /scripts/build-hostapd.sh "${mount_point}/tmp/build-hostapd.sh"
            sudo chmod +x "${mount_point}/tmp/build-hostapd.sh"

            chroot_run "${mount_point}" /tmp/build-hostapd.sh

            if [[ -x "${mount_point}/usr/local/bin/hostapd" ]]; then
                log_info "hostapd compiled and installed successfully"
                chroot_run "${mount_point}" /usr/local/bin/hostapd -v 2>&1 | head -3
            else
                die "hostapd compilation failed - binary not found"
            fi

            safe_rm "${hostapd_build_dir}"
            safe_rm "${mount_point}/tmp/build-hostapd.sh"
        else
            log_info "Installing hostapd from APT (Development mode)"
            chroot_run "${mount_point}" bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get install -qy --no-install-recommends hostapd"
            # Create compatibility symlink for systemd service
            chroot_run "${mount_point}" ln -sf /usr/sbin/hostapd /usr/local/bin/hostapd
        fi
    else
        log_info "hostapd not enabled in profile, skipping installation"
    fi
}

# Install Pi-hole (source or official)
install_pihole() {
    local mount_point=$1
    if is_service_enabled "pihole" 2>/dev/null; then
        if is_build_from_source_enabled "pihole_ftl" 2>/dev/null; then
            log_info "Installing Pi-hole from GitHub source (Production mode)"

            # Use the dedicated FTL build script for production source builds
            sudo cp /scripts/build-pihole-ftl.sh "${mount_point}/tmp/build-pihole-ftl.sh"
            sudo chmod +x "${mount_point}/tmp/build-pihole-ftl.sh"
            chroot_run "${mount_point}" /tmp/build-pihole-ftl.sh

            if [[ -x "${mount_point}/usr/local/bin/pihole-FTL" ]]; then
                log_info "Pi-hole FTL compiled and installed successfully"
                chroot_run "${mount_point}" /usr/local/bin/pihole-FTL --version
            else
                log_error "Pi-hole FTL compilation failed - binary not found"
            fi
            safe_rm "${mount_point}/tmp/build-pihole-ftl.sh"
        else
            log_info "Installing Pi-hole using official installer (Development mode)"

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
            # Mock only in /usr/bin as the installer will overwrite it with the real binary.
            # We avoid /usr/local/bin to prevent it from taking precedence over the real binary in the PATH.
            sudo mkdir -p "${mount_point}/usr/bin"
            sudo ln -sf /bin/true "${mount_point}/usr/bin/pihole-FTL"
            sudo ln -sf /bin/true "${mount_point}/usr/bin/pihole"

            # 3. Download and run installer as requested
            log_info "Downloading Pi-hole installer..."
            # Note: We download on host then copy to ensure network success
            wget -qO /tmp/basic-install.sh https://install.pi-hole.net
            sudo cp /tmp/basic-install.sh "${mount_point}/tmp/basic-install.sh"
            sudo chmod +x "${mount_point}/tmp/basic-install.sh"

            # 4. Pre-seed pihole.toml (v6) to provide paths for gravity.sh
            # The installer calls gravity.sh which uses pihole-FTL to read these paths.
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
            # Override architecture detection to ARMv7 to avoid 'armv6' download errors
            # Set PIHOLE_SKIP_OS_CHECK to bypass OS validation in chroot
            # PROTECT resolv.conf: Installer tries to point it to 127.0.0.1 which fails in chroot
            sudo chattr +i "${mount_point}/etc/resolv.conf" 2>/dev/null || true
            chroot_run "${mount_point}" bash -c "export PIHOLE_SKIP_OS_CHECK=true; bash /tmp/basic-install.sh --unattended" || {
                sudo chattr -i "${mount_point}/etc/resolv.conf" 2>/dev/null || true
                die "Pi-hole installer failed. This is a critical component."
            }
            sudo chattr -i "${mount_point}/etc/resolv.conf" 2>/dev/null || true

            # Cleanup mocks
            sudo rm -f "${mount_point}/usr/bin/pihole-FTL"
            sudo rm -f "${mount_point}/usr/bin/pihole"

            # RESTORE DNS: Pi-hole installer overwrites /etc/resolv.conf
            log_info "Restoring build-time resolv.conf for chroot"
            sudo mkdir -p "${mount_point}/etc"
            # Ensure it's a file, not a broken symlink from the installer
            sudo rm -f "${mount_point}/etc/resolv.conf"
            sudo tee "${mount_point}/etc/resolv.conf" > /dev/null <<EOF
# DNS for chroot build environment (restored after Pi-hole install)
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
            safe_rm "${mount_point}/tmp/basic-install.sh"
        fi
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

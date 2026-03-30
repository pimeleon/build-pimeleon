#!/bin/bash
# Library for service installation functions

# Install hostapd (artifact or APT)
install_hostapd() {
    local mount_point=$1
    if is_service_enabled "hostapd" 2>/dev/null; then
        # 1. Try to fetch pre-built artifact (local cache or registry)
        sudo mkdir -p "${CACHE_DIR}/pimeleon-downloads"
        if get_pimeleon_apps_artifact "hostapd" "${RPI_ARCH:-armhf}" "${CACHE_DIR}/pimeleon-downloads"; then
            log_info "Installing hostapd from artifact"
            sudo tar -xzf "${CACHE_DIR}/pimeleon-downloads/hostapd.tar.gz" -C "${mount_point}/"
            return
        fi

        die "Failed to fetch hostapd artifact — cannot continue"
    else
        die "hostapd is not enabled in profile — cannot build Pimeleon image without it"
    fi
}

# Install Pi-hole (artifact-only — no from-source installs)
install_pihole() {
    local mount_point=$1
    if is_service_enabled "pihole" 2>/dev/null; then
        sudo mkdir -p "${CACHE_DIR}/pimeleon-downloads"
        if get_pimeleon_apps_artifact "pihole" "${RPI_ARCH:-armhf}" "${CACHE_DIR}/pimeleon-downloads"; then
            log_info "Installing Pi-hole from artifact"
            sudo tar -xzf "${CACHE_DIR}/pimeleon-downloads/pihole.tar.gz" -C "${mount_point}/"
            return
        fi

        die "Failed to fetch pihole artifact — cannot continue"
    else
        die "pihole is not enabled in profile — cannot build Pimeleon image without it"
    fi
}

# Install Tor (artifact or APT)
install_tor() {
    local mount_point=$1
    if is_service_enabled "tor" 2>/dev/null; then
        # 1. Try to fetch pre-built artifact (local cache or registry)
        sudo mkdir -p "${CACHE_DIR}/pimeleon-downloads"
        if get_pimeleon_apps_artifact "tor" "${RPI_ARCH:-armhf}" "${CACHE_DIR}/pimeleon-downloads"; then
            log_info "Installing Tor from artifact"
            sudo tar -xzf "${CACHE_DIR}/pimeleon-downloads/tor.tar.gz" -C "${mount_point}/"
            return
        fi

        die "Failed to fetch tor artifact — cannot continue"
    else
        die "tor is not enabled in profile — cannot build Pimeleon image without it"
    fi
}

# Install dnscrypt-proxy (artifact or APT)
install_dnscrypt_proxy() {
    local mount_point=$1
    if is_service_enabled "dnscrypt_proxy" 2>/dev/null; then
        # 1. Try to fetch pre-built artifact (local cache or registry)
        sudo mkdir -p "${CACHE_DIR}/pimeleon-downloads"
        if get_pimeleon_apps_artifact "dnscrypt-proxy" "${RPI_ARCH:-armhf}" "${CACHE_DIR}/pimeleon-downloads"; then
            log_info "Installing dnscrypt-proxy from artifact"
            sudo tar -xzf "${CACHE_DIR}/pimeleon-downloads/dnscrypt-proxy.tar.gz" -C "${mount_point}/"
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
    sudo mkdir -p "${CACHE_DIR}/pimeleon-downloads"
    if get_pimeleon_apps_artifact "wpa_supplicant" "${RPI_ARCH:-armhf}" "${CACHE_DIR}/pimeleon-downloads"; then
        log_info "Installing wpa_supplicant from artifact"
        sudo tar -xzf "${CACHE_DIR}/pimeleon-downloads/wpa_supplicant.tar.gz" -C "${mount_point}/"
        return
    fi

    die "Failed to fetch wpa_supplicant artifact — cannot continue"
}

# Install privoxy (artifact only)
install_privoxy() {
    local mount_point=$1
    if is_service_enabled "privoxy" 2>/dev/null; then
        sudo mkdir -p "${CACHE_DIR}/pimeleon-downloads"
        if get_pimeleon_apps_artifact "privoxy" "${RPI_ARCH:-armhf}" "${CACHE_DIR}/pimeleon-downloads"; then
            log_info "Installing privoxy from artifact"
            sudo tar -xzf "${CACHE_DIR}/pimeleon-downloads/privoxy.tar.gz" -C "${mount_point}/"
            return
        fi

        die "Failed to fetch privoxy artifact — cannot continue"
    else
        die "privoxy is not enabled in profile — cannot build Pimeleon image without it"
    fi
}

#!/bin/bash
set -euo pipefail

# Generate Privoxy filters from AdBlock Plus lists
# Runs on x86 builder, outputs to chroot
# Caches generated filters to avoid regenerating on every build

# shellcheck disable=SC1091
# shellcheck disable=SC1091
source /scripts/common.sh

MOUNT_POINT=$1
PRIVOXY_DIR="${MOUNT_POINT}/etc/privoxy"
AB2P_DIR="${PRIVOXY_DIR}/ab2p"
CACHE_DIR="${CACHE_DIR:-/cache}/privoxy-filters"
CACHE_MAX_AGE_DAYS=7

log_info "Generating Privoxy filters"

# Create directories
sudo mkdir -p "${AB2P_DIR}" "${CACHE_DIR}"

# Check cache age
CACHE_VALID=false
if [[ -f "${CACHE_DIR}/ab2p/ab2p.action" ]]; then
    CACHE_AGE=$(find "${CACHE_DIR}/ab2p/ab2p.action" -mtime -${CACHE_MAX_AGE_DAYS} 2>/dev/null | wc -l)
    if [[ "${CACHE_AGE}" -gt 0 ]]; then
        CACHE_VALID=true
        log_info "Using cached Privoxy filters (less than ${CACHE_MAX_AGE_DAYS} days old)"
    else
        log_info "Cache expired, regenerating filters"
    fi
else
    log_info "No cache found, generating filters"
fi

if [[ "${CACHE_VALID}" == "true" ]]; then
    # Use cached filters
    sudo cp -r "${CACHE_DIR}/ab2p/"* "${AB2P_DIR}/" 2>/dev/null || true
    if [[ -f "${CACHE_DIR}/ads.yoyo.action" ]]; then
        sudo cp "${CACHE_DIR}/ads.yoyo.action" "${PRIVOXY_DIR}/"
    fi
else
    # Generate new filters
    TEMP_DIR="/tmp/privoxy-filters"
    mkdir -p "${TEMP_DIR}"

    # AdBlock Plus filter lists to convert
    FILTER_LISTS=(
        "https://easylist-downloads.adblockplus.org/easylist.txt"
        "https://easylist-downloads.adblockplus.org/easyprivacy.txt"
        "https://easylist-downloads.adblockplus.org/fanboy-social.txt"
        "https://easylist-downloads.adblockplus.org/antiadblockfilters.txt"
        "https://easylist-downloads.adblockplus.org/abp-filters-anti-cv.txt"
    )

    # Run adblock2privoxy
    log_info "Converting AdBlock lists to Privoxy format (this may take a while)"
    if command -v adblock2privoxy &> /dev/null; then
        sudo mkdir -p "${TEMP_DIR}/ab2p"
        # Set data directory for adblock2privoxy (overrides hardcoded path)
        # The package looks for templates in $adblock2privoxy_datadir/templates/
        export adblock2privoxy_datadir="/usr/share/adblock2privoxy"
        sudo -E adblock2privoxy \
            -p "${TEMP_DIR}/ab2p" \
            -w "${TEMP_DIR}/www" \
            "${FILTER_LISTS[@]}" 2>&1 | tail -20 || log_warn "adblock2privoxy completed with warnings"

        # Copy to chroot and cache
        if [[ -d "${TEMP_DIR}/ab2p" ]] && [[ -n "$(sudo ls -A "${TEMP_DIR}/ab2p" 2>/dev/null)" ]]; then
            sudo cp -r "${TEMP_DIR}/ab2p/"* "${AB2P_DIR}/"
            # Update cache
            sudo mkdir -p "${CACHE_DIR}/ab2p"
            sudo cp -r "${TEMP_DIR}/ab2p/"* "${CACHE_DIR}/ab2p/"
            sudo chown -R "$(id -u):$(id -g)" "${CACHE_DIR}"
            log_info "Generated and cached ab2p filters"
        else
            log_warn "adblock2privoxy produced no output"
        fi
    else
        log_warn "adblock2privoxy not found, skipping AdBlock list conversion"
    fi

    # Download ads.yoyo.org blocklist
    log_info "Downloading ads.yoyo.org blocklist"
    YOYO_URL="https://pgl.yoyo.org/as/serverlist.php?hostformat=privoxy&showintro=0&mimetype=plaintext"
    YOYO_FILE="${PRIVOXY_DIR}/ads.yoyo.action"

    if curl -fsSL -o "${TEMP_DIR}/ads.yoyo.raw" "${YOYO_URL}"; then
        # Add blocking action header
        echo '{+block{Ad domains from pgl.yoyo.org} +handle-as-empty-document}' | \
            sudo tee "${YOYO_FILE}" > /dev/null
        cat "${TEMP_DIR}/ads.yoyo.raw" | sudo tee -a "${YOYO_FILE}" > /dev/null
        # Cache it
        sudo cp "${YOYO_FILE}" "${CACHE_DIR}/ads.yoyo.action" 2>/dev/null || true
        log_info "Downloaded and cached ads.yoyo.org blocklist"
    else
        log_warn "Failed to download ads.yoyo.org blocklist"
    fi

    # Cleanup temp
    sudo rm -rf "${TEMP_DIR}"
fi

# Set ownership
sudo chown -R root:root "${PRIVOXY_DIR}"
sudo chmod -R 644 "${AB2P_DIR}"/* 2>/dev/null || true
sudo chmod 755 "${AB2P_DIR}"

log_info "Privoxy filter generation complete"

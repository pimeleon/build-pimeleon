#!/bin/bash
# Build hostapd from source inside chroot
# Source must already be extracted to /tmp/hostapd-build/hostap
# This script runs INSIDE the chroot via chroot_run

set -euo pipefail

BUILD_DIR="/tmp/hostapd-build/hostap/hostapd"
INSTALL_DIR="/usr/local/bin"

echo "Building hostapd from source..."

cd "${BUILD_DIR}"

# Create .config for Pi 3B+ (BCM43455 - 2.4GHz AP, 802.11n)
# Based on working config from production gateway
cat > .config << 'EOF'
# hostapd build configuration for Pimeleon Router (Pi 3B+)
# Tuned for BCM43455 chip capabilities

# Driver interface for nl80211
CONFIG_DRIVER_NL80211=y
CONFIG_LIBNL32=y

# IEEE 802.11n (HT) - supported on Pi 3B+
CONFIG_IEEE80211N=y

# WPA/WPA2 (WPA3/SAE not supported by BCM43455 firmware in AP mode)
CONFIG_RSN_PREAUTH=y

# WPS (Wi-Fi Protected Setup) - disabled for security
#CONFIG_WPS=y
#CONFIG_WPS2=y

# EAP server (disabled - only needed for WPS/enterprise)
#CONFIG_EAP=y
#CONFIG_EAP_WSC=y

# IPv6 support
CONFIG_IPV6=y

# Debug/logging
CONFIG_DEBUG_FILE=y
CONFIG_DEBUG_SYSLOG=y
EOF

echo "Compiling hostapd..."
make clean 2>/dev/null || true
make -j$(nproc)

echo "Installing hostapd to ${INSTALL_DIR}..."
install -m 755 hostapd "${INSTALL_DIR}/hostapd"
install -m 755 hostapd_cli "${INSTALL_DIR}/hostapd_cli"

# Verify installation
echo "Verifying installation..."
"${INSTALL_DIR}/hostapd" -v || true

echo "hostapd build completed successfully!"

#!/bin/bash
# Build Tor from source inside chroot
# This script runs INSIDE the chroot via chroot_run

set -euo pipefail

TOR_VERSION="${1:-0.4.8.13}" # Fallback version
BUILD_DIR="/tmp/tor-build"
INSTALL_PREFIX="/usr/local"
NPROC=$(nproc)

echo "Building Tor ${TOR_VERSION} from source..."
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Install build dependencies
# Update package lists
apt-get update -qq
apt-get upgrade -qy
apt-get install -qy --no-install-recommends \
    wget \
    ca-certificates \
    build-essential \
    libevent-dev \
    libssl-dev \
    zlib1g-dev \
    libsystemd-dev \
    pkg-config

# Download and extract Tor source
echo "Downloading Tor source..."
wget -q "https://dist.torproject.org/tor-${TOR_VERSION}.tar.gz"
tar -xzf "tor-${TOR_VERSION}.tar.gz"
cd "tor-${TOR_VERSION}"

# Configure and build
echo "Configuring Tor..."
./configure \
    --prefix="${INSTALL_PREFIX}" \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --enable-systemd \
    --disable-asciidoc \
    --disable-manpage \
    --disable-html-manual

echo "Compiling Tor (this may take a while)..."
make -j"${NPROC}"

# Install
echo "Installing Tor..."
make install

# Create tor user and group if they don't exist
groupadd -r debian-tor 2>/dev/null || true
useradd -r -g debian-tor -s /usr/sbin/nologin -d /var/lib/tor debian-tor 2>/dev/null || true

# Create directories
mkdir -p /var/lib/tor /var/log/tor /run/tor
chown -R debian-tor:debian-tor /var/lib/tor /var/log/tor /run/tor
chmod 700 /var/lib/tor

# Cleanup build directory
echo "Cleaning up build artifacts..."
cd /
rm -rf "${BUILD_DIR}"

# Verify installation
echo "Verifying installation..."
"${INSTALL_PREFIX}/bin/tor" --version

echo "Tor build completed successfully!"

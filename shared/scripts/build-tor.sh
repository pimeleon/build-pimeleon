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
echo "Installing build dependencies..."
apt-get update -qq
apt-get install -qy --no-install-recommends \
    git \
    ca-certificates \
    build-essential \
    libevent-dev \
    libssl-dev \
    zlib1g-dev \
    libsystemd-dev \
    pkg-config \
    autoconf \
    automake

# Clone Tor source
echo "Cloning Tor repository from GitLab..."
git clone https://gitlab.torproject.org/tpo/core/tor.git "${BUILD_DIR}/tor"
cd "${BUILD_DIR}/tor"

# Checkout specific version if provided, otherwise use default branch (latest)
if [[ "${TOR_VERSION}" != "latest" ]]; then
    echo "Checking out version tor-${TOR_VERSION}..."
    # Try to checkout tag, fallback to branch if tag doesn't exist
    git checkout "tor-${TOR_VERSION}" 2>/dev/null || git checkout "${TOR_VERSION}" || echo "Warning: Could not checkout ${TOR_VERSION}, using default branch"
fi

# Generate build scripts
echo "Running autogen.sh..."
./autogen.sh

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

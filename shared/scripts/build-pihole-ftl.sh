#!/bin/bash
# Build Pi-hole FTL from source inside chroot
# This script runs INSIDE the chroot via chroot_run
# Builds latest from git with minimal features (no web UI auth)

set -euo pipefail

BUILD_DIR="/tmp/ftl-build"
INSTALL_PREFIX="/usr/local"
NPROC=$(nproc)

# Versions for dependencies
NETTLE_VERSION="3.10.2"
MBEDTLS_VERSION="3.6.4"

echo "Building Pi-hole FTL from source..."
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Update package lists
apt-get update -qq
apt-get upgrade -qy
apt-get install -qy --no-install-recommends \
    git \
    wget \
    ca-certificates \
    build-essential \
    libgmp-dev \
    m4 \
    cmake \
    libidn2-dev \
    libunistring-dev \
    libreadline-dev \
    xxd \
    pkg-config \
    libcap-dev

# Build libnettle (required for DNSSEC)
echo "Building libnettle ${NETTLE_VERSION}..."
cd "${BUILD_DIR}"
wget -q "https://ftp.gnu.org/gnu/nettle/nettle-${NETTLE_VERSION}.tar.gz"
tar -xzf "nettle-${NETTLE_VERSION}.tar.gz"
cd "nettle-${NETTLE_VERSION}"
./configure --enable-static --disable-shared --disable-documentation \
    --libdir=/usr/local/lib
make -j"${NPROC}"
make install
ldconfig

# Build libmbedtls (required for TLS)
echo "Building mbedTLS ${MBEDTLS_VERSION}..."
cd "${BUILD_DIR}"
wget -q "https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-${MBEDTLS_VERSION}/mbedtls-${MBEDTLS_VERSION}.tar.bz2"
tar -xjf "mbedtls-${MBEDTLS_VERSION}.tar.bz2"
cd "mbedtls-${MBEDTLS_VERSION}"
# Enable threading support
sed -i 's|//#define MBEDTLS_THREADING_C|#define MBEDTLS_THREADING_C|' include/mbedtls/mbedtls_config.h
sed -i 's|//#define MBEDTLS_THREADING_PTHREAD|#define MBEDTLS_THREADING_PTHREAD|' include/mbedtls/mbedtls_config.h
mkdir -p build && cd build
cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DENABLE_TESTING=OFF \
    -DENABLE_PROGRAMS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    ..
make -j"${NPROC}"
make install
ldconfig

# Clone and build FTL
echo "Cloning Pi-hole FTL..."
cd "${BUILD_DIR}"
git clone --depth 1 https://github.com/pi-hole/FTL.git
cd FTL

# Build FTL
echo "Building FTL..."
mkdir -p build && cd build
cmake -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_DNSMASQ=OFF \
    ..
make -j"${NPROC}"

# Install binary
echo "Installing FTL..."
install -m 755 src/pihole-FTL "${INSTALL_PREFIX}/bin/pihole-FTL"

# Create symlink for pihole CLI
ln -sf "${INSTALL_PREFIX}/bin/pihole-FTL" "${INSTALL_PREFIX}/bin/pihole"

# Create pihole user and group
groupadd -r pihole 2>/dev/null || true
useradd -r -g pihole -s /usr/sbin/nologin -d /var/lib/pihole pihole 2>/dev/null || true

# Create directories
mkdir -p /etc/pihole /var/lib/pihole /var/log/pihole /run/pihole
chown -R pihole:pihole /etc/pihole /var/lib/pihole /var/log/pihole /run/pihole
chmod 775 /etc/pihole

# Set capabilities for non-root operation
setcap 'cap_net_bind_service,cap_net_raw,cap_net_admin,cap_sys_nice,cap_chown+eip' "${INSTALL_PREFIX}/bin/pihole-FTL" || true

# Cleanup build directory
echo "Cleaning up build artifacts..."
cd /
rm -rf "${BUILD_DIR}"

# Verify installation
echo "Verifying installation..."
"${INSTALL_PREFIX}/bin/pihole-FTL" --version

echo "Pi-hole FTL build completed successfully!"

#!/bin/bash
# Build dnscrypt-proxy from source inside chroot
# This script runs INSIDE the chroot via chroot_run

set -euo pipefail

# Version from: https://github.com/DNSCrypt/dnscrypt-proxy/releases
DNSCRYPT_VERSION="${1:-2.1.5}"
BUILD_DIR="/tmp/dnscrypt-build"
INSTALL_PREFIX="/usr/local"
GO_VERSION="1.22.2" # Required for modern dnscrypt-proxy

echo "Building dnscrypt-proxy ${DNSCRYPT_VERSION} from source..."
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Install build dependencies
echo "Installing build dependencies..."
apt-get update -qq
apt-get install -qy --no-install-recommends \
    curl \
    git \
    ca-certificates \
    build-essential

# Install Go (architecture aware)
ARCH=$(uname -m)
case "${ARCH}" in
    x86_64)  GO_ARCH="amd64" ;;
    aarch64) GO_ARCH="arm64" ;;
    armv7l)  GO_ARCH="armv6l" ;; # RPi 3B+ uses armv7l but Go uses armv6l for compatibility
    *)       echo "Unsupported architecture: ${ARCH}"; exit 1 ;;
esac

echo "Installing Go ${GO_VERSION} for ${GO_ARCH}..."
curl -sSL "https://golang.org/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -o go.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Clone dnscrypt-proxy source
echo "Cloning dnscrypt-proxy repository..."
git clone --depth 1 --branch "${DNSCRYPT_VERSION}" https://github.com/DNSCrypt/dnscrypt-proxy.git "${BUILD_DIR}/dnscrypt-proxy"
cd "${BUILD_DIR}/dnscrypt-proxy/dnscrypt-proxy"

# Build binary
echo "Compiling dnscrypt-proxy..."
go build -ldflags="-s -w" -mod=vendor

# Install
echo "Installing dnscrypt-proxy..."
mkdir -p "${INSTALL_PREFIX}/bin"
cp dnscrypt-proxy "${INSTALL_PREFIX}/bin/"

# Create user and group if they don't exist
groupadd -r _dnscrypt-proxy 2>/dev/null || true
useradd -r -g _dnscrypt-proxy -s /usr/sbin/nologin -d /var/cache/dnscrypt-proxy _dnscrypt-proxy 2>/dev/null || true

# Setup directories
mkdir -p /etc/dnscrypt-proxy /var/cache/dnscrypt-proxy /var/log/dnscrypt-proxy
chown -R _dnscrypt-proxy:_dnscrypt-proxy /var/cache/dnscrypt-proxy /var/log/dnscrypt-proxy
chmod 750 /var/cache/dnscrypt-proxy /var/log/dnscrypt-proxy

# Cleanup build artifacts
echo "Cleaning up build artifacts..."
cd /
rm -rf "${BUILD_DIR}"
rm -rf /usr/local/go

# Verify installation
echo "Verifying installation..."
"${INSTALL_PREFIX}/bin/dnscrypt-proxy" -version

echo "dnscrypt-proxy build completed successfully!"

#!/bin/bash
# Check and optionally install local build dependencies
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Required packages
REQUIRED_PACKAGES=(
    debootstrap
    qemu-user-static
    binfmt-support
    kpartx
    parted
    ansible
    dosfstools
    e2fsprogs
    rsync
    xz-utils
)

# Optional but recommended
OPTIONAL_PACKAGES=(
    ansible-lint
    shellcheck
)

echo "=== Pimeleon Local Build Dependency Checker ==="
echo ""

check_command() {
    command -v "$1" &> /dev/null
}

check_package() {
    dpkg -l "$1" &> /dev/null 2>&1
}

MISSING_REQUIRED=()
MISSING_OPTIONAL=()

echo "Checking required dependencies..."
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if check_package "$pkg"; then
        echo -e "  ${GREEN}✓${NC} $pkg"
    else
        echo -e "  ${RED}✗${NC} $pkg"
        MISSING_REQUIRED+=("$pkg")
    fi
done

echo ""
echo "Checking optional dependencies..."
for pkg in "${OPTIONAL_PACKAGES[@]}"; do
    if check_package "$pkg"; then
        echo -e "  ${GREEN}✓${NC} $pkg"
    else
        echo -e "  ${YELLOW}○${NC} $pkg (optional)"
        MISSING_OPTIONAL+=("$pkg")
    fi
done

echo ""

# Check binfmt registration
echo "Checking ARM emulation..."
if [[ -f /proc/sys/fs/binfmt_misc/qemu-arm ]]; then
    echo -e "  ${GREEN}✓${NC} qemu-arm registered"
else
    echo -e "  ${RED}✗${NC} qemu-arm not registered"
    MISSING_REQUIRED+=("binfmt-registration")
fi

echo ""

# Summary
if [[ ${#MISSING_REQUIRED[@]} -eq 0 ]]; then
    echo -e "${GREEN}All required dependencies are installed!${NC}"
    echo "You can run: ./scripts/build-local.sh"
else
    echo -e "${RED}Missing required packages: ${MISSING_REQUIRED[*]}${NC}"
    echo ""
    echo "Install with:"
    echo -e "${YELLOW}sudo apt update && sudo apt install -y ${MISSING_REQUIRED[*]}${NC}"

    if [[ " ${MISSING_REQUIRED[*]} " =~ "binfmt-registration" ]]; then
        echo ""
        echo "To register ARM emulation:"
        echo -e "${YELLOW}sudo systemctl restart binfmt-support${NC}"
    fi

    # Offer to install
    if [[ "${1:-}" == "--install" ]]; then
        echo ""
        echo "Installing missing packages..."
        sudo apt update
        sudo apt install -y "${MISSING_REQUIRED[@]}"
        sudo systemctl restart binfmt-support || { echo -e "${RED}Failed to restart binfmt-support — ARM emulation will not work${NC}"; exit 1; }
        echo -e "${GREEN}Done!${NC}"
    else
        echo ""
        echo "Run with --install to automatically install missing packages:"
        echo "  $0 --install"
    fi

    exit 1
fi

if [[ ${#MISSING_OPTIONAL[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}Optional packages not installed: ${MISSING_OPTIONAL[*]}${NC}"
    echo "Install with: sudo apt install -y ${MISSING_OPTIONAL[*]}"
fi

exit 0

#!/bin/bash
set -euo pipefail

# Stage 2: Customize system
# Install packages and apply configurations

# shellcheck disable=SC1091
# shellcheck disable=SC1091
source /scripts/common.sh
# shellcheck disable=SC1091
# shellcheck disable=SC1091
source /scripts/lib-services.sh

# Setup cleanup trap for error handling
trap 'cleanup_on_exit' EXIT ERR INT TERM

WORK_DIR=$1
IMAGE_PATH=$2
# CLEANUP_IMAGE_PATH="${IMAGE_PATH}"
MOUNT_POINT="${WORK_DIR}/mount"
BOOT_MOUNT="${WORK_DIR}/boot"
IMAGE_NAME="pimeleon-${TARGET_PLATFORM:-rpi3-bookworm}"
ANSIBLE_LOG_FILE="/output/ansible-${IMAGE_NAME}.log"

# Ansible directory from docker-compose environment
SHARED_ANSIBLE_DIR="${ANSIBLE_DIR:-/ansible}"

log_info "Starting system customization"

# Mount image
mount_image "${IMAGE_PATH}" "${MOUNT_POINT}"
LOOP_DEVICE="${CLEANUP_LOOP_DEVICE}"

# Boot partition is already mounted at ${MOUNT_POINT}/boot by mount_image function
BOOT_MOUNT="${MOUNT_POINT}/boot"

# Setup chroot
setup_chroot "${MOUNT_POINT}"

# Configure APT cache for chroot environment early
configure_chroot_apt_proxy "${MOUNT_POINT}"

# Protect resolv.conf before any apt-get runs.
# systemd-resolved (in SYSTEM_PKGS) replaces /etc/resolv.conf with a symlink to
# ../run/systemd/resolve/stub-resolv.conf (127.0.0.53), which is unreachable inside
# the chroot namespace and breaks all subsequent apt-get operations.
sudo chattr +i "${MOUNT_POINT}/etc/resolv.conf" 2>/dev/null || true

# Update sources.list to ensure it matches current configuration (even if using old base cache)
log_info "Updating APT sources"
if [[ "${RPI_ARCH:-armhf}" == "arm64" ]]; then
    # arm64: standard Debian repos + non-free-firmware for bookworm+
    sudo tee "${MOUNT_POINT}/etc/apt/sources.list" > /dev/null <<EOF
deb http://deb.debian.org/debian ${RASPBIAN_VERSION:-bookworm} main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security ${RASPBIAN_VERSION:-bookworm}-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${RASPBIAN_VERSION:-bookworm}-updates main contrib non-free non-free-firmware
EOF
else
    # armhf: Raspbian repos
    sudo tee "${MOUNT_POINT}/etc/apt/sources.list" > /dev/null <<EOF
deb ${RASPBIAN_MIRROR:-http://raspbian.raspberrypi.com/raspbian/} ${RASPBIAN_VERSION:-bookworm} main contrib non-free rpi
deb-src ${RASPBIAN_MIRROR:-http://raspbian.raspberrypi.com/raspbian/} ${RASPBIAN_VERSION:-bookworm} main contrib non-free rpi
EOF

    # Ensure Raspbian keyring is present for verification
    if [ ! -f "${MOUNT_POINT}/etc/apt/trusted.gpg.d/raspbian-archive-keyring.gpg" ]; then
        log_info "Installing Raspbian archive keyring"
        wget -qO- http://archive.raspbian.org/raspbian.public.key | \
            gpg --dearmor | \
            sudo tee "${MOUNT_POINT}/etc/apt/trusted.gpg.d/raspbian-archive-keyring.gpg" > /dev/null \
            || die "Failed to fetch or install Raspbian GPG keyring"
        sudo chmod 644 "${MOUNT_POINT}/etc/apt/trusted.gpg.d/raspbian-archive-keyring.gpg"
    fi
fi

# Ensure raspi.list is also present (Raspberry Pi Foundation repo)
if [ ! -f "${MOUNT_POINT}/etc/apt/sources.list.d/raspi.list" ]; then
    log_info "Restoring raspi.list"
    sudo tee "${MOUNT_POINT}/etc/apt/sources.list.d/raspi.list" > /dev/null <<EOF
deb [signed-by=/etc/apt/keyrings/raspberrypi-archive-keyring.gpg] http://archive.raspberrypi.com/debian/ ${RASPBIAN_VERSION:-bookworm} main
EOF
fi

# Fix APT keyring deprecation warning (migrate from legacy trusted.gpg)
migrate_apt_keyring "${MOUNT_POINT}"

# Update package lists
log_info "Updating package lists"
chroot_run "${MOUNT_POINT}" apt-get -q update
chroot_run "${MOUNT_POINT}" apt-get -q -y upgrade

# Define package categories for better maintenance
SYSTEM_PKGS=(
    "systemd" "systemd-sysv" "systemd-resolved" "udev" "dbus" "policykit-1"
    "locales" "locales-all" "tzdata" "fake-hwclock" "cron" "rsyslog" "logrotate"
    "sudo" "parted" "pkg-config" "ca-certificates" "apt-transport-https"
    "openssh-server" "zram-tools" "dphys-swapfile" "at"
)

SHELL_PKGS=(
    "bash-completion" "zsh" "tmux" "mc" "vim" "nano" "less" "file" "tree"
    "unzip" "zip" "bc" "jq" "strace" "lsof" "procps" "psmisc"
)

NET_CORE_PKGS=(
    "iproute2" "net-tools" "nftables" "iptables" "ipset" "conntrack" "tcpdump"
    "dnsutils" "wget" "curl" "nmap" "mtr-tiny" "traceroute" "whois" "socat"
    "bind9" "bind9utils"
)

NET_ROUTER_PKGS=(
    "bridge-utils" "vlan" "ppp" "pppoeconf" "wireguard-tools"
    "wireless-tools" "wireless-regdb" "rfkill" "iw"
    "isc-dhcp-server"
)

MONITOR_PKGS=(
    "htop" "atop" "iotop" "iftop" "nethogs" "nload" "bmon" "bwm-ng"
    "sysstat" "iptraf-ng" "vnstat" "wavemon" "speedtest-cli" "sysbench"
)

HARDWARE_PKGS=(
    "usbutils" "lshw" "hdparm" "ethtool"
)

BUILD_DEPS=(
    "build-essential" "libevent-dev" "libnl-3-dev" "libnl-genl-3-dev"
    "libssl-dev" "libzstd-dev" "sqlite3" "python3" "python3-pip"
    "python3-venv" "python3-apt" "nodejs"
)

# Install essential packages by category for better visibility
log_info "Installing system core packages"
chroot_run "${MOUNT_POINT}" apt-get install -qq -y --no-install-recommends "${SYSTEM_PKGS[@]}" &>/dev/null

log_info "Installing shell and utility packages"
chroot_run "${MOUNT_POINT}" apt-get install -qq -y --no-install-recommends "${SHELL_PKGS[@]}" &>/dev/null

log_info "Installing core networking packages"
chroot_run "${MOUNT_POINT}" apt-get install -qq -y --no-install-recommends "${NET_CORE_PKGS[@]}" &>/dev/null

log_info "Installing routing and wireless packages"
chroot_run "${MOUNT_POINT}" apt-get install -qq -y --no-install-recommends "${NET_ROUTER_PKGS[@]}" &>/dev/null

log_info "Installing monitoring and diagnostics packages"
chroot_run "${MOUNT_POINT}" apt-get install -qq -y --no-install-recommends "${MONITOR_PKGS[@]}" &>/dev/null

log_info "Installing hardware-specific packages"
chroot_run "${MOUNT_POINT}" apt-get install -qq -y --no-install-recommends "${HARDWARE_PKGS[@]}" &>/dev/null

log_info "Installing build dependencies and runtime environments"
chroot_run "${MOUNT_POINT}" apt-get install -qq -y --no-install-recommends "${BUILD_DEPS[@]}" &>/dev/null

# Restore and protect resolv.conf (systemd-resolved might have converted it to a symlink)
log_info "Restoring and protecting resolv.conf"
sudo chattr -i "${MOUNT_POINT}/etc/resolv.conf" 2>/dev/null || true
sudo rm -f "${MOUNT_POINT}/etc/resolv.conf"
sudo tee "${MOUNT_POINT}/etc/resolv.conf" > /dev/null <<EOF
# DNS for chroot build environment (restored after package installation)
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
sudo chattr +i "${MOUNT_POINT}/etc/resolv.conf" 2>/dev/null || true

# Verify Python3 installation (required for Ansible)
log_info "Verifying Python3 installation..."
if ! chroot_run "${MOUNT_POINT}" python3 --version > /dev/null 2>&1; then
    log_error "Python3 not installed - Ansible will fail"
    die "Python3 installation failed"
fi
PYTHON_VER=$(chroot_run "${MOUNT_POINT}" python3 --version)
log_info "Python3 installed: ${PYTHON_VER}"

# Install WiFi firmware (may fail if non-free not available)
log_info "Installing WiFi firmware"
chroot_run "${MOUNT_POINT}" apt-get install -qq -y --no-install-recommends \
    firmware-brcm80211 || die "WiFi firmware (firmware-brcm80211) installation failed — wireless AP cannot function"

# Install Pi-specific packages (kernel and firmware)
log_info "Installing Raspberry Pi kernel and firmware"
chroot_run "${MOUNT_POINT}" apt-get install -qq -y --no-install-recommends \
    raspberrypi-kernel \
    raspberrypi-bootloader

# Verify Pi boot firmware was installed to boot partition
log_info "Verifying Pi boot firmware installation"
FIRMWARE_OK=true
[[ -f "${BOOT_MOUNT}/bootcode.bin" ]] || { log_error "bootcode.bin not found"; FIRMWARE_OK=false; }
[[ -f "${BOOT_MOUNT}/start.elf" ]] || { log_error "start.elf not found"; FIRMWARE_OK=false; }
[[ -f "${BOOT_MOUNT}/fixup.dat" ]] || { log_error "fixup.dat not found"; FIRMWARE_OK=false; }
[[ -f "${BOOT_MOUNT}/kernel7.img" ]] || { log_error "kernel7.img not found"; FIRMWARE_OK=false; }
[[ -f "${BOOT_MOUNT}/bcm2710-rpi-3-b-plus.dtb" ]] || { log_error "Pi 3B+ device tree not found"; FIRMWARE_OK=false; }
[[ -d "${BOOT_MOUNT}/overlays" ]] || { log_error "Boot overlays not found"; FIRMWARE_OK=false; }
if [[ "$FIRMWARE_OK" == "true" ]]; then
    log_info "All Pi boot firmware files verified"
else
    die "Some firmware files missing - image will not boot"
fi

# Install basic networking tools
log_info "Installing basic networking tools"
chroot_run "${MOUNT_POINT}" apt-get install -qq -y --no-install-recommends \
    bridge-utils \
    isc-dhcp-server \
    rfkill \
    wireless-regdb

# Install core services from registry apps artifacts
install_hostapd "${MOUNT_POINT}"
install_wpasupplicant "${MOUNT_POINT}"
install_pihole "${MOUNT_POINT}"
install_tor "${MOUNT_POINT}"

# Install DNS server packages (dnscrypt-proxy uses pre-built binary, not APT)
log_info "Installing DNS server packages"
chroot_run "${MOUNT_POINT}" apt-get install -qq -y --no-install-recommends \
    bind9 \
    bind9utils

# Install security packages
log_info "Installing security packages"
chroot_run "${MOUNT_POINT}" apt-get install -qq -y --no-install-recommends \
    fail2ban

# Install proxy packages from registry apps artifacts
install_privoxy "${MOUNT_POINT}"

# Generate Privoxy filters from AdBlock lists (runs on x86, outputs to chroot)
log_info "Generating Privoxy ad-blocking filters"
if [[ -x /scripts/generate-privoxy-filters.sh ]]; then
    /scripts/generate-privoxy-filters.sh "${MOUNT_POINT}"
else
    die "FATAL: Privoxy filter generator not found at /scripts/generate-privoxy-filters.sh"
fi

# Disable NetworkManager (Bookworm default) in favor of systemd-networkd
log_info "Configuring systemd-networkd as network manager"
chroot_run "${MOUNT_POINT}" systemctl disable NetworkManager 2>/dev/null || log_warn "Could not disable NetworkManager — service may not be installed"
chroot_run "${MOUNT_POINT}" systemctl disable ModemManager 2>/dev/null || log_warn "Could not disable ModemManager — service may not be installed"
chroot_run "${MOUNT_POINT}" systemctl mask NetworkManager 2>/dev/null || log_warn "Could not mask NetworkManager — it may still start on boot"

# Mask wpa_supplicant (we use hostapd for AP mode, not client mode)
log_info "Disabling and masking wpa_supplicant service"
chroot_run "${MOUNT_POINT}" systemctl disable wpa_supplicant 2>/dev/null || log_warn "Could not disable wpa_supplicant — service may not be installed"
chroot_run "${MOUNT_POINT}" systemctl mask wpa_supplicant 2>/dev/null || log_warn "Could not mask wpa_supplicant — it may still start on boot"

# Configure system
log_info "Configuring system"

# Enable IP forwarding
sudo mkdir -p "${MOUNT_POINT}/etc/sysctl.d"
sudo tee "${MOUNT_POINT}/etc/sysctl.d/30-ip-forward.conf" > /dev/null <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.all.log_martians=1
net.ipv4.tcp_syncookies=1
net.ipv4.icmp_echo_ignore_broadcasts=1
EOF
sudo chmod 644 "${MOUNT_POINT}/etc/sysctl.d/30-ip-forward.conf"

# Note: systemd-networkd configuration handled by Ansible (network-setup.yml)
sudo mkdir -p "${MOUNT_POINT}/etc/systemd/network"
sudo chmod 755 "${MOUNT_POINT}/etc/systemd/network"

# Note: Locale generation handled in stage3-optimize.sh to avoid duplication

# Configure SSH
sudo sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' "${MOUNT_POINT}/etc/ssh/sshd_config"
sudo sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' "${MOUNT_POINT}/etc/ssh/sshd_config"
echo "AllowUsers pim" | sudo tee -a "${MOUNT_POINT}/etc/ssh/sshd_config" > /dev/null

# Create standard groups if they don't exist
log_info "Ensuring standard groups exist"
for group in adm dialout cdrom users netdev; do
    chroot_run "${MOUNT_POINT}" groupadd -f "$group" 2>/dev/null || true
done

# Create Pi-specific groups
log_info "Creating Pi-specific groups"
for group in gpio i2c spi; do
    chroot_run "${MOUNT_POINT}" groupadd -f -r "$group" || true
done

# Create Pimeleon management user (UID/GID 1000 like default pi user)
log_info "Creating pim management user"
# Ensure pim group is GID 1000
chroot_run "${MOUNT_POINT}" groupadd -f -g 1000 pim
# Ensure pim user is UID 1000
chroot_run "${MOUNT_POINT}" useradd --create-home -u 1000 -s /bin/zsh -g pim -G adm,dialout,cdrom,users,netdev,gpio,i2c,spi pim || true

# Create Pimeleon service users (using same pim group)
log_info "Creating Pimeleon service users"
chroot_run "${MOUNT_POINT}" useradd -r -s /usr/sbin/nologin -g pim -d /opt/pimeleon/api pim-api || true
chroot_run "${MOUNT_POINT}" useradd -r -s /usr/sbin/nologin -g pim -d /opt/pimeleon/proxy pim-proxy || true
chroot_run "${MOUNT_POINT}" useradd -r -s /usr/sbin/nologin -g pim -d /var/lib/ngrok pim-ngrok || true

# Create pihole system user (required by Ansible pihole-ftl-setup tasks)
log_info "Creating pihole system user"
chroot_run "${MOUNT_POINT}" groupadd -f -r pihole || true
chroot_run "${MOUNT_POINT}" useradd -r -s /usr/sbin/nologin -g pihole -d /etc/pihole pihole || true

# Verify users
log_info "Verifying Pimeleon users"
chroot_run "${MOUNT_POINT}" id pim || true
chroot_run "${MOUNT_POINT}" id pim-api || true
chroot_run "${MOUNT_POINT}" id pim-proxy || true
chroot_run "${MOUNT_POINT}" id pim-ngrok || true
chroot_run "${MOUNT_POINT}" id pihole || true

# Ensure home directory exists (fallback if useradd -m fails)
sudo mkdir -p "${MOUNT_POINT}/home/pim"
chroot_run "${MOUNT_POINT}" chown pim:pim /home/pim
chroot_run "${MOUNT_POINT}" chmod 755 /home/pim
# Set password - use environment variable or default thematic word
TEMP_PASSWORD="${PIMELEON_INITIAL_PASSWORD:-netblox}"
echo "pim:${TEMP_PASSWORD}" | chroot_run "${MOUNT_POINT}" chpasswd
echo "${TEMP_PASSWORD}" | sudo tee "${OUTPUT_DIR}/pim-initial-password.txt" > /dev/null
sudo chmod 600 "${OUTPUT_DIR}/pim-initial-password.txt"
log_warn "Initial password saved to: ${OUTPUT_DIR}/pim-initial-password.txt"

# Create full sudo access for pim user (password-less)
sudo mkdir -p "${MOUNT_POINT}/etc/sudoers.d"
sudo chmod 755 "${MOUNT_POINT}/etc/sudoers.d"
cat > /tmp/sudoers-pim << EOF
pim ALL=(ALL) NOPASSWD: ALL
EOF
sudo cp /tmp/sudoers-pim "${MOUNT_POINT}/etc/sudoers.d/010_pim-admin"
sudo chmod 440 "${MOUNT_POINT}/etc/sudoers.d/010_pim-admin"

# =============================================================================
# Download source/binary files BEFORE Ansible (chroot has no network access)
# =============================================================================
log_info "Downloading files for chroot installation"

# Create download directory in cache (outside image to save space)
sudo mkdir -p "${CACHE_DIR}/pimeleon-downloads"
sudo chmod 755 "${CACHE_DIR}/pimeleon-downloads"
sudo chown "${PIMELEON_USER}:${PIMELEON_GROUP}" "${CACHE_DIR}/pimeleon-downloads"

# Fetch pre-built binaries from registry (production only)
# Source is routed by get_pimeleon_apps_artifact: GitLab registry (dev CI) or GitHub releases (prod CI)
# Non-production profiles fall back to APT sources via Ansible
pkg="dnscrypt-proxy"
if [[ "${PIMELEON_PROFILE}" == "production" ]]; then
    if ! get_pimeleon_apps_artifact "${pkg}" "${RPI_ARCH}" "${CACHE_DIR}/pimeleon-downloads"; then
        if is_service_enabled "${pkg//-/_}" 2>/dev/null; then
            die "Failed to fetch ${pkg} from apps registry and it is enabled in this profile."
        else
            log_warn "Failed to fetch ${pkg} from apps registry; service is not enabled, continuing."
        fi
    fi
else
    log_info "Profile '${PIMELEON_PROFILE}': skipping artifact fetch for ${pkg}, APT source will be used"
fi

# Pi-hole FTL is built from source (see build-pihole-ftl.sh)
# Tor is installed from official Tor Project repository (see tor-setup.yml)

# Copy downloads into chroot for Ansible to find
log_info "Copying downloads into chroot"
sudo mkdir -p "${MOUNT_POINT}/tmp/pimeleon-downloads"
if [[ -n "$(ls -A "${CACHE_DIR}/pimeleon-downloads" 2>/dev/null)" ]]; then
    sudo cp -r "${CACHE_DIR}/pimeleon-downloads"/* "${MOUNT_POINT}/tmp/pimeleon-downloads/"
else
    log_info "No files found in ${CACHE_DIR}/pimeleon-downloads to copy"
fi
sudo chmod -R 755 "${MOUNT_POINT}/tmp/pimeleon-downloads"

# Install ngrok (for remote access tunneling)
log_info "Downloading ngrok"
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc 2>&1 | chroot_run "${MOUNT_POINT}" tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com bookworm main" 2>&1 | chroot_run "${MOUNT_POINT}" tee /etc/apt/sources.list.d/ngrok.list
log_info "Installing ngrok for remote access tunneling"
chroot_run "${MOUNT_POINT}" apt-get -qq update
chroot_run "${MOUNT_POINT}" apt-get -qq -y upgrade
chroot_run "${MOUNT_POINT}" apt-get -qq -y install ngrok

# =============================================================================
# Install Pimeleon Web UI and API
# =============================================================================
log_info "Installing Pimeleon Web UI and API..."

# Destination paths inside chroot image
PIMELEON_API_DEST="${MOUNT_POINT}/opt/pimeleon/api"
PIMELEON_PROXY_DEST="${MOUNT_POINT}/opt/pimeleon/proxy"
PIMELEON_UI_DEST="${MOUNT_POINT}/opt/pimeleon/ui"

log_info "Building Pimeleon Web UI and API from GitLab source..."
log_info "pirouter-ui is not published via pi-router-apps artifacts; building from source is expected."

# Fix for 504 Gateway Timeout and SSL issues with local GitLab
git config --global http.sslVerify false
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999
git config --global core.compression 0

# Configurable via environment variables (see docker-compose.yml)
PIMELEON_UI_REPO="${PIMELEON_UI_REPO:-https://gitlab.pirouter.dev/pimeleon/pirouter-ui.git}"

# Branch: env var takes precedence, otherwise select from CI branch context
if [[ -n "${PIMELEON_UI_BRANCH:-}" ]]; then
    # Use explicitly configured branch
    :
elif [[ "${CI_PIPELINE_SOURCE:-}" == "merge_request_event" ]]; then
    case "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}" in
        develop)
            PIMELEON_UI_BRANCH="preview"
            ;;
        release/*)
            PIMELEON_UI_BRANCH="master"
            ;;
        *)
            PIMELEON_UI_BRANCH="master"
            ;;
    esac
elif [[ "${CI_COMMIT_BRANCH:-}" == "develop" ]]; then
    PIMELEON_UI_BRANCH="preview"
elif [[ "${CI_COMMIT_BRANCH:-}" == release/* ]]; then
    PIMELEON_UI_BRANCH="master"
else
    PIMELEON_UI_BRANCH="master"
fi

PIMELEON_UI_BUILD_DIR="${CACHE_DIR}/pirouter-ui"

# Ensure build directory is writable (CI cache may be root-owned)
sudo mkdir -p "${PIMELEON_UI_BUILD_DIR}"
sudo chown "$(id -u):$(id -g)" "${PIMELEON_UI_BUILD_DIR}"

# Construct authenticated URL if token is available
if [[ -n "${PIMELEON_UI_BUILD_TOKEN:-}" ]]; then
    PIMELEON_UI_REPO_AUTH="${PIMELEON_UI_REPO/https:\/\//https:\/\/oauth2:${PIMELEON_UI_BUILD_TOKEN}@}"
else
    PIMELEON_UI_REPO_AUTH="${PIMELEON_UI_REPO}"
fi

# Clone or update repo
if [[ -d "${PIMELEON_UI_BUILD_DIR}/.git" ]]; then
    log_info "Updating existing pirouter-ui clone..."
    # Discard any local changes (e.g. from pnpm add in previous build run)
    git -C "${PIMELEON_UI_BUILD_DIR}" reset --hard HEAD
    # Fetch specific branch (shallow clones don't have remote tracking refs)
    git -C "${PIMELEON_UI_BUILD_DIR}" fetch origin "${PIMELEON_UI_BRANCH}"
    # Create/reset local branch from FETCH_HEAD (origin/branch doesn't exist in shallow clones)
    git -C "${PIMELEON_UI_BUILD_DIR}" checkout -B "${PIMELEON_UI_BRANCH}" FETCH_HEAD
else
    log_info "Cloning pirouter-ui from ${PIMELEON_UI_REPO} (branch: ${PIMELEON_UI_BRANCH})..."
    git clone --depth 1 --branch "${PIMELEON_UI_BRANCH}" "${PIMELEON_UI_REPO_AUTH}" "${PIMELEON_UI_BUILD_DIR}"
fi

# Build UI and API using pnpm (Node.js 22 installed in builder image)
log_info "Building Pimeleon UI and API (${PIMELEON_PROFILE} mode, branch: ${PIMELEON_UI_BRANCH})..."
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
pushd "${PIMELEON_UI_BUILD_DIR}" > /dev/null

# Configure pnpm caching and always use the default registry.
pnpm config set store-dir "${CACHE_DIR}/.pnpm-store"
log_info "pnpm: using cache at ${CACHE_DIR}/.pnpm-store with default registry"

# Always start with clean node_modules to avoid store mismatch (ERR_NPM_UNEXPECTED_STORE)
# or included dependencies conflicts (ERR_INCLUDED_DEPS_CONFLICT)
rm -rf node_modules

# Ensure jose is present in the API package
log_info "pnpm: preparing workspace dependencies"
pnpm --filter "@pi-router/api" add jose
export CI=true
log_info "pnpm: running frozen install"
pnpm install --frozen-lockfile
log_info "pnpm: running build"
NODE_ENV="${PIMELEON_PROFILE}" pnpm build
popd > /dev/null

# =============================================================================
# Copy Pimeleon UI/API files to chroot (if available)
# =============================================================================
log_info "Copying Pimeleon UI/API files (if available)"

# Determine source paths from built artifacts
PIMELEON_UI_SRC="${PIMELEON_UI_BUILD_DIR}/apps/ui/dist/spa"
PIMELEON_PROXY_SRC="${PIMELEON_UI_BUILD_DIR}/apps/api/.output/server"

# FastAPI source (Python - no build step)
if [[ -d "${PIMELEON_UI_BUILD_DIR}/apps/api-fastapi" ]]; then
    PIMELEON_API_SRC="${PIMELEON_UI_BUILD_DIR}/apps/api-fastapi"
    log_info "Pimeleon FastAPI found at ${PIMELEON_API_SRC}"
else
    PIMELEON_API_SRC="${CONFIG_DIR}/services/api-fastapi"
fi

log_info "Pimeleon UI source: ${PIMELEON_UI_SRC}"
log_info "Pimeleon Proxy source: ${PIMELEON_PROXY_SRC}"

# Copy FastAPI server if available
if [[ -d "${PIMELEON_API_SRC}" ]] && [[ -f "${PIMELEON_API_SRC}/requirements.txt" ]]; then
    log_info "Copying Pimeleon Python FastAPI server files"
    sudo mkdir -p "${PIMELEON_API_DEST}"
    sudo rsync -a --exclude '__pycache__' --exclude '*.pyc' --exclude 'logs' --exclude 'venv' --exclude '.env' --exclude '.env.example' "${PIMELEON_API_SRC}/" "${PIMELEON_API_DEST}/"
    log_info "Python FastAPI server copied: $(du -sh "${PIMELEON_API_DEST}" | cut -f1)"
else
    die "FATAL: Python FastAPI server not found at ${PIMELEON_API_SRC}"
fi

# Copy Nitro proxy if available
if [[ -d "${PIMELEON_PROXY_SRC}" ]] && [[ -f "${PIMELEON_PROXY_SRC}/index.mjs" ]]; then
    log_info "Copying pre-built Pimeleon Nuxt proxy files"
    sudo mkdir -p "${PIMELEON_PROXY_DEST}"
    sudo rsync -a --exclude '.nuxt' --exclude 'logs' "${PIMELEON_PROXY_SRC}/" "${PIMELEON_PROXY_DEST}/"
    log_info "Nitro proxy copied: $(du -sh "${PIMELEON_PROXY_DEST}" | cut -f1)"
else
    die "FATAL: Nitro proxy not found at ${PIMELEON_PROXY_SRC}"
fi

# Copy Quasar SPA if available
if [[ -d "${PIMELEON_UI_SRC}" ]] && [[ -f "${PIMELEON_UI_SRC}/index.html" ]]; then
    log_info "Copying pre-built Pimeleon Quasar UI files"
    sudo mkdir -p "${PIMELEON_UI_DEST}"
    sudo rsync -a --exclude 'node_modules' --exclude '.quasar' --exclude 'logs' "${PIMELEON_UI_SRC}/" "${PIMELEON_UI_DEST}/"
    log_info "Quasar SPA copied: $(du -sh "${PIMELEON_UI_DEST}" | cut -f1)"
else
    die "FATAL: Quasar SPA not found at ${PIMELEON_UI_SRC}"
fi

# Set interim ownership to root:root for chroot operations
if [[ -d "${MOUNT_POINT}/opt/pimeleon" ]]; then
    log_info "Setting interim ownership to root:root for /opt/pimeleon"
    sudo chown -R root:root "${MOUNT_POINT}/opt/pimeleon"
fi

# =============================================================================
# Ansible Configuration (Monorepo Structure)
# =============================================================================

# Paths for monorepo structure
SHARED_VARS_DIR="${SHARED_ANSIBLE_DIR}/vars"
PLAYBOOKS_DIR="${SHARED_ANSIBLE_DIR}/playbooks"

# Apply Ansible playbooks if available
if [[ -d "${PLAYBOOKS_DIR}" ]] && [[ -n "$(ls -A "${PLAYBOOKS_DIR}"/*.yml 2>/dev/null)" ]]; then
    log_info "Applying Ansible playbooks (Monorepo mode)"
    log_info "App: ${TARGET_PLATFORM:-not set}"
    export ANSIBLE_CONFIG="${SHARED_ANSIBLE_DIR}/ansible.cfg"
    export ANSIBLE_HOST_KEY_CHECKING=False
    export PYTHONUNBUFFERED=1

    # Determine platform group from environment (3B+ -> raspberrypi_3bplus, 4B -> raspberrypi_4b)
    PLATFORM_GROUP="raspberrypi_$(echo "${PIMELEON_RPI_MODEL:-3B+}" | tr '[:upper:]' '[:lower:]' | tr -d '+')"
    log_info "Platform group: ${PLATFORM_GROUP}"

    # Create temporary inventory with platform group membership
    proxy_vars=""
    if has_apt_proxy; then
        proxy_url="http://${APT_PROXY}"
        proxy_vars="http_proxy=\"${proxy_url}\"
https_proxy=\"${proxy_url}\"
no_proxy=\"localhost,127.0.0.1,local\""
    fi

    cat > "${WORK_DIR}/inventory" <<EOF
[all]
pimeleon ansible_connection=chroot ansible_host=${MOUNT_POINT}

[raspberrypi]
pimeleon

[${PLATFORM_GROUP}]
pimeleon

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOF

    # Append proxy vars if available (avoids empty variable expansion issues)
    if [[ -n "${proxy_vars}" ]]; then
        echo "${proxy_vars}" >> "${WORK_DIR}/inventory"
    fi

    # Setup group_vars directory structure for Ansible
    mkdir -p "${WORK_DIR}/group_vars/all"
    mkdir -p "${WORK_DIR}/group_vars/raspberrypi"
    mkdir -p "${WORK_DIR}/group_vars/${PLATFORM_GROUP}"

    # Layer 1: Copy shared common vars (lowest priority)
    # Exclude profiles/ dir — only the selected profile should be loaded (copied at line 512)
    if [[ -d "${SHARED_VARS_DIR}/common" ]]; then
        log_info "Loading shared common vars from: ${SHARED_VARS_DIR}/common"
        find "${SHARED_VARS_DIR}/common" -maxdepth 1 -not -name profiles -not -path "${SHARED_VARS_DIR}/common" \
            -exec cp -R {} "${WORK_DIR}/group_vars/all/" \;
    fi

    # Layer 2: Copy platform vars (raspberrypi family)
    if [[ -d "${SHARED_VARS_DIR}/platform/raspberrypi" ]]; then
        log_info "Loading platform vars from: ${SHARED_VARS_DIR}/platform/raspberrypi"
        if [[ -n "$(ls -A "${SHARED_VARS_DIR}/platform/raspberrypi/" 2>/dev/null)" ]]; then
            cp -R "${SHARED_VARS_DIR}/platform/raspberrypi/"* "${WORK_DIR}/group_vars/raspberrypi/"
        fi
    fi

    # Copy profile vars to all group
    if [[ -f "${SHARED_VARS_DIR}/common/profiles/${PIMELEON_PROFILE}.yml" ]]; then
        cp "${SHARED_VARS_DIR}/common/profiles/${PIMELEON_PROFILE}.yml" "${WORK_DIR}/group_vars/all/profile.yml"
        log_info "Using profile: ${PIMELEON_PROFILE}"
    fi

    # Run playbooks with platform, version, app, and profile extra-vars
    for playbook in "${PLAYBOOKS_DIR}"/*.yml; do
        log_info "Running playbook: $(basename "$playbook")"
        sudo -E ansible-playbook \
            -i "${WORK_DIR}/inventory" \
            --extra-vars "platform_model=${PIMELEON_RPI_MODEL:-3B+}" \
            --extra-vars "rpi_arch=${RPI_ARCH:-armhf}" \
            --extra-vars "debian_version=${RASPBIAN_VERSION:-bookworm}" \
            --extra-vars "pimeleon_profile=${PIMELEON_PROFILE}" \
            --extra-vars "pimeleon_app=${TARGET_PLATFORM:-}" \
            --extra-vars "pimeleon_initial_password=${PIMELEON_INITIAL_PASSWORD:-netblox}" \
            --extra-vars "pimeleon_ap_name=${PIMELEON_AP_NAME:-Pimeleon}" \
            "$playbook" 2>&1 | tee -a "${ANSIBLE_LOG_FILE}" || die "Playbook failed: $playbook. See ${ANSIBLE_LOG_FILE} for details."
    done
else
    die "FATAL: No Ansible playbooks found at: ${PLAYBOOKS_DIR}"
fi

# Copy custom configs if available
if [[ -d "${CONFIG_DIR}" ]]; then
    log_info "Copying custom configurations"

    # Network configs
    if [[ -d "${CONFIG_DIR}/network" ]] && [[ -n "$(ls -A "${CONFIG_DIR}/network"/* 2>/dev/null)" ]]; then
        sudo cp -R "${CONFIG_DIR}/network/"* "${MOUNT_POINT}/etc/network/"
    fi

    # Security configs
    if [[ -d "${CONFIG_DIR}/security" ]] && [[ -n "$(ls -A "${CONFIG_DIR}/security"/* 2>/dev/null)" ]]; then
        sudo cp -R "${CONFIG_DIR}/security/"* "${MOUNT_POINT}/etc/"
    fi

    # Service configs
    if [[ -d "${CONFIG_DIR}/services" ]] && [[ -n "$(ls -A "${CONFIG_DIR}/services"/* 2>/dev/null)" ]]; then
        sudo cp -R "${CONFIG_DIR}/services/"* "${MOUNT_POINT}/etc/"
    fi
fi

# Clean up APT cache configuration from final image
if [[ -f "${MOUNT_POINT}/etc/apt/apt.conf.d/01proxy" ]]; then
    log_info "Removing APT cache configuration from final image"
    sudo rm -f "${MOUNT_POINT}/etc/apt/apt.conf.d/01proxy"
fi

# Configure static resolv.conf for production
# This must be done AFTER all network operations (git clone, apt, etc.)
log_info "Configuring static DNS resolver for production"
sudo chattr -i "${MOUNT_POINT}/etc/resolv.conf" 2>/dev/null || true
sudo rm -f "${MOUNT_POINT}/etc/resolv.conf"
sudo tee "${MOUNT_POINT}/etc/resolv.conf" > /dev/null <<EOF
# DNS for chroot build environment
nameserver 8.8.8.8
nameserver 1.1.1.1
# nameserver 127.0.0.1
EOF
sudo chmod 644 "${MOUNT_POINT}/etc/resolv.conf"

# Get version information
log_info "Generating version info: ${IMAGE_PATH}.version.txt"
cat > "${IMAGE_PATH}.version.txt" <<EOF
Build Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Raspbian Version: ${RASPBIAN_VERSION:-bookworm}
Kernel Version: $(chroot_run "${MOUNT_POINT}" uname -r || echo "unknown")
Pi Model: ${PIMELEON_RPI_MODEL:-3B+}
Builder Version: 1.0.0
EOF

# Verify stage completion
verify_stage 2 "${MOUNT_POINT}"

# Cleanup chroot
cleanup_chroot "${MOUNT_POINT}"

# Unmount image (includes boot partition)
unmount_image "${MOUNT_POINT}" "${LOOP_DEVICE}"

log_info "Stage 2 completed successfully"

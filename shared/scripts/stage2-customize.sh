#!/bin/bash
set -euo pipefail

# Stage 2: Customize system
# Install packages and apply configurations

source /scripts/common.sh

# Setup cleanup trap for error handling
trap cleanup_on_exit EXIT ERR INT

WORK_DIR=$1
IMAGE_PATH=$2
MOUNT_POINT="${WORK_DIR}/mount"
BOOT_MOUNT="${WORK_DIR}/boot"
IMAGE_NAME="pimeleon-${PIMELEON_APP:-rpi3-bookworm}"
ANSIBLE_LOG_FILE="/output/ansible-${IMAGE_NAME}.log"

log_info "Starting system customization"

# Mount image
LOOP_DEVICE=$(mount_image "${IMAGE_PATH}" "${MOUNT_POINT}")

# Boot partition is already mounted at ${MOUNT_POINT}/boot by mount_image function
BOOT_MOUNT="${MOUNT_POINT}/boot"

# Setup chroot
setup_chroot "${MOUNT_POINT}"

# Configure APT cache for chroot environment early
if [[ -n "${APT_CACHE_SERVER:-}" ]]; then
    log_info "Configuring APT cache for chroot environment"
    sudo mkdir -p "${MOUNT_POINT}/etc/apt/apt.conf.d"
    sudo tee "${MOUNT_POINT}/etc/apt/apt.conf.d/01proxy" > /dev/null <<EOF
# APT Cache Configuration for Build Process
Acquire::http::Proxy "http://${APT_CACHE_SERVER}:${APT_CACHE_PORT:-3142}";
# Longer timeouts for slow cache/upstream responses
Acquire::http::Timeout "120";
Acquire::https::Timeout "120";
Acquire::Retries "3";
EOF
fi

# Update sources.list with current mirror (overrides cached base image)
log_info "Updating APT sources to use: ${RASPBIAN_MIRROR:-http://raspbian.raspberrypi.com/raspbian/}"
sudo tee "${MOUNT_POINT}/etc/apt/sources.list" > /dev/null <<EOF
deb ${RASPBIAN_MIRROR:-http://raspbian.raspberrypi.com/raspbian/} ${RASPBIAN_VERSION:-bookworm} main contrib non-free rpi
deb-src ${RASPBIAN_MIRROR:-http://raspbian.raspberrypi.com/raspbian/} ${RASPBIAN_VERSION:-bookworm} main contrib non-free rpi
EOF

# Fix APT keyring deprecation warning (migrate from legacy trusted.gpg)
if [ -f "${MOUNT_POINT}/etc/apt/trusted.gpg" ]; then
    log_info "Migrating legacy APT keyring to new format"
    sudo mkdir -p "${MOUNT_POINT}/etc/apt/trusted.gpg.d"
    sudo gpg --no-default-keyring \
        --keyring "${MOUNT_POINT}/etc/apt/trusted.gpg" \
        --export 2>/dev/null | \
        sudo gpg --no-default-keyring \
            --keyring "gnupg-ring:${MOUNT_POINT}/etc/apt/trusted.gpg.d/raspbian-archive-keyring.gpg" \
            --import 2>/dev/null || true
    sudo chmod 644 "${MOUNT_POINT}/etc/apt/trusted.gpg.d/raspbian-archive-keyring.gpg" 2>/dev/null || true
    sudo rm -f "${MOUNT_POINT}/etc/apt/trusted.gpg"
fi

# Update package lists
log_info "Updating package lists"
chroot_run "${MOUNT_POINT}" apt-get -q update

# Install essential packages (full router stack)
log_info "Installing essential packages"
chroot_run "${MOUNT_POINT}" apt-get install -qy --no-install-recommends \
    arp-scan \
    arping \
    arptables \
    at \
    atop \
    bash-completion \
    bc \
    bmon \
    build-essential \
    bwm-ng \
    ca-certificates \
    conntrack \
    curl \
    dbus \
    dnstop \
    dnsutils \
    dstat \
    ethtool \
    fake-hwclock \
    file \
    fping \
    hdparm \
    htop \
    iftop \
    ifstat \
    iotop \
    iperf3 \
    iproute2 \
    jq \
    less \
    libnl-3-dev \
    libnl-genl-3-dev \
    libssl-dev \
    locales \
    locales-all \
    logrotate \
    lshw \
    lsof \
    man-db \
    manpages \
    mc \
    mtr-tiny \
    nano \
    ncdu \
    netcat-openbsd \
    net-tools \
    nethogs \
    nftables \
    nload \
    iptables \
    ipset \
    iptraf-ng \
    nmap \
    nodejs \
    openssh-server \
    parted \
    pkg-config \
    policykit-1 \
    ppp \
    pppoeconf \
    procps \
    psmisc \
    python3 \
    python3-apt \
    python3-pip \
    python3-venv \
    rsyslog \
    smartmontools \
    socat \
    speedtest-cli \
    sqlite3 \
    strace \
    sudo \
    sysbench \
    sysstat \
    systemd \
    systemd-sysv \
    tcpdump \
    tmux \
    traceroute \
    tree \
    tshark \
    udev \
    unzip \
    usbutils \
    vim \
    vlan \
    vnstat \
    wavemon \
    wget \
    whiptail \
    whois \
    wireguard-tools \
    wireless-tools \
    zip \
    zram-tools \
    zsh

# Verify Python3 installation (required for Ansible)
if ! chroot_run "${MOUNT_POINT}" python3 --version; then
    log_error "Python3 not installed - Ansible will fail"
    die "Python3 installation failed"
fi
log_info "Python3 installed: $(chroot_run "${MOUNT_POINT}" python3 --version)"

# Install WiFi firmware (may fail if non-free not available)
log_info "Installing WiFi firmware"
chroot_run "${MOUNT_POINT}" apt-get install -qy --no-install-recommends \
    firmware-brcm80211 || log_warn "WiFi firmware not available, wireless may not work"

# Install Pi-specific packages (kernel, bootloader, firmware)
log_info "Installing Raspberry Pi kernel and firmware"
chroot_run "${MOUNT_POINT}" apt-get install -qy --no-install-recommends \
    raspberrypi-kernel \
    libraspberrypi-bin

# Verify Pi boot firmware was installed to boot partition
log_info "Verifying Pi boot firmware installation"
FIRMWARE_OK=true
[[ -f "${BOOT_MOUNT}/bootcode.bin" ]] || { log_warn "bootcode.bin not found"; FIRMWARE_OK=false; }
[[ -f "${BOOT_MOUNT}/start.elf" ]] || { log_warn "start.elf not found"; FIRMWARE_OK=false; }
[[ -f "${BOOT_MOUNT}/fixup.dat" ]] || { log_warn "fixup.dat not found"; FIRMWARE_OK=false; }
[[ -f "${BOOT_MOUNT}/kernel7.img" ]] || { log_warn "kernel7.img not found"; FIRMWARE_OK=false; }
[[ -f "${BOOT_MOUNT}/bcm2710-rpi-3-b-plus.dtb" ]] || { log_warn "Pi 3B+ device tree not found"; FIRMWARE_OK=false; }
[[ -d "${BOOT_MOUNT}/overlays" ]] || { log_warn "Boot overlays not found"; FIRMWARE_OK=false; }
if [[ "$FIRMWARE_OK" == "true" ]]; then
    log_info "All Pi boot firmware files verified"
else
    die "Some firmware files missing - image will not boot"
fi

# Install basic networking tools (hostapd compiled from source separately)
log_info "Installing basic networking tools"
chroot_run "${MOUNT_POINT}" apt-get install -qy --no-install-recommends \
    bridge-utils \
    isc-dhcp-server \
    wireless-regdb \
    wpasupplicant

# Build hostapd from official w1.fi source (WPA3/SAE support)
log_info "Building hostapd from source with WPA3/SAE support"
HOSTAPD_VERSION="hostap_2_10"
HOSTAPD_BUILD_DIR="${MOUNT_POINT}/tmp/hostapd-build"

# Clone hostap repository on builder host (has network access)
sudo mkdir -p "${HOSTAPD_BUILD_DIR}"
if [[ ! -d "${HOSTAPD_BUILD_DIR}/hostap" ]]; then
    log_info "Cloning hostap repository (${HOSTAPD_VERSION})..."
    sudo git clone --depth 1 --branch "${HOSTAPD_VERSION}" \
        https://git.w1.fi/hostap.git "${HOSTAPD_BUILD_DIR}/hostap"
fi

# Copy build script into chroot
sudo cp /scripts/build-hostapd.sh "${MOUNT_POINT}/tmp/build-hostapd.sh"
sudo chmod +x "${MOUNT_POINT}/tmp/build-hostapd.sh"

# Build hostapd inside chroot (ARM cross-compilation via QEMU)
log_info "Compiling hostapd inside chroot (this may take a while)..."
chroot_run "${MOUNT_POINT}" /tmp/build-hostapd.sh

# Verify hostapd installed
if [[ -x "${MOUNT_POINT}/usr/local/bin/hostapd" ]]; then
    log_info "hostapd compiled and installed successfully"
    chroot_run "${MOUNT_POINT}" /usr/local/bin/hostapd -v 2>&1 | head -3 || true
else
    die "hostapd compilation failed - binary not found"
fi

# Cleanup build artifacts
sudo rm -rf "${HOSTAPD_BUILD_DIR}"
sudo rm -f "${MOUNT_POINT}/tmp/build-hostapd.sh"

# Install DNS server packages
log_info "Installing DNS server packages"
chroot_run "${MOUNT_POINT}" apt-get install -qy --no-install-recommends \
    bind9 \
    bind9utils \
    dnscrypt-proxy

# Install security packages
log_info "Installing security packages"
chroot_run "${MOUNT_POINT}" apt-get install -qy --no-install-recommends \
    fail2ban

# Install proxy packages
log_info "Installing proxy packages"
chroot_run "${MOUNT_POINT}" apt-get install -qy --no-install-recommends \
    privoxy

# Generate Privoxy filters from AdBlock lists (runs on x86, outputs to chroot)
log_info "Generating Privoxy ad-blocking filters"
if [[ -x /scripts/generate-privoxy-filters.sh ]]; then
    /scripts/generate-privoxy-filters.sh "${MOUNT_POINT}"
else
    log_warn "Privoxy filter generator not found, skipping"
fi

# Disable NetworkManager (Bookworm default) in favor of systemd-networkd
log_info "Configuring systemd-networkd as network manager"
chroot_run "${MOUNT_POINT}" systemctl disable NetworkManager 2>/dev/null || true
chroot_run "${MOUNT_POINT}" systemctl disable ModemManager 2>/dev/null || true
chroot_run "${MOUNT_POINT}" systemctl mask NetworkManager 2>/dev/null || true

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

# Configure locales (en_IE default, plus common languages)
log_info "Configuring locales"

# Create locale.alias if missing (prevents warning during locale-gen)
if [ ! -f "${MOUNT_POINT}/etc/locale.alias" ]; then
    sudo touch "${MOUNT_POINT}/etc/locale.alias"
fi
if [ ! -e "${MOUNT_POINT}/usr/share/locale/locale.alias" ]; then
    sudo ln -sf /etc/locale.alias "${MOUNT_POINT}/usr/share/locale/locale.alias"
fi

sudo tee "${MOUNT_POINT}/etc/locale.gen" > /dev/null <<EOF
en_IE.UTF-8 UTF-8
en_US.UTF-8 UTF-8
es_ES.UTF-8 UTF-8
ru_RU.UTF-8 UTF-8
uk_UA.UTF-8 UTF-8
zh_CN.UTF-8 UTF-8
ko_KR.UTF-8 UTF-8
EOF
chroot_run "${MOUNT_POINT}" locale-gen
chroot_run "${MOUNT_POINT}" update-locale LANG=en_IE.UTF-8

# Configure SSH
sudo sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' "${MOUNT_POINT}/etc/ssh/sshd_config"
sudo sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' "${MOUNT_POINT}/etc/ssh/sshd_config"
echo "AllowUsers pim" | sudo tee -a "${MOUNT_POINT}/etc/ssh/sshd_config" > /dev/null

# Create standard groups if they don't exist
log_info "Ensuring standard groups exist"
for group in adm dialout cdrom audio video plugdev games users input netdev; do
    chroot_run "${MOUNT_POINT}" groupadd -f "$group" 2>/dev/null || true
done

# Create Pi-specific groups
log_info "Creating Pi-specific groups"
for group in gpio i2c spi; do
    chroot_run "${MOUNT_POINT}" groupadd -f -r "$group" || true
done

# Create Pimeleon service group and users
log_info "Creating Pimeleon service group and users"
chroot_run "${MOUNT_POINT}" groupadd -f -r pim
chroot_run "${MOUNT_POINT}" useradd -r -s /usr/sbin/nologin -g pim -d /opt/pimeleon/api pim-api || true
chroot_run "${MOUNT_POINT}" useradd -r -s /usr/sbin/nologin -g pim -d /opt/pimeleon/proxy pim-proxy || true
chroot_run "${MOUNT_POINT}" useradd -r -s /usr/sbin/nologin -g pim -d /var/lib/ngrok pim-ngrok || true

# Verify users
log_info "Verifying Pimeleon users"
chroot_run "${MOUNT_POINT}" id pim-api || true
chroot_run "${MOUNT_POINT}" id pim-proxy || true
chroot_run "${MOUNT_POINT}" id pim-ngrok || true

# Create pim management user (full sudo via sudoers.d, not sudo group)
log_info "Creating pim management user"
chroot_run "${MOUNT_POINT}" useradd --create-home -s /bin/zsh -g pim -G adm,dialout,cdrom,audio,video,plugdev,games,users,input,netdev,gpio,i2c,spi pim || true
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

# Create full sudo access for pim user (passwordless)
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

# Version numbers
DNSCRYPT_VERSION="2.1.15"
PIHOLE_VERSION="6.3"

# Create download directory in cache (outside image to save space)
DOWNLOAD_DIR="${CACHE_DIR}/pimeleon-downloads"
sudo mkdir -p "${DOWNLOAD_DIR}"
sudo chmod 755 "${DOWNLOAD_DIR}"
sudo chown "$(id -u):$(id -g)" "${DOWNLOAD_DIR}"

# Download dnscrypt-proxy (ARM binary - no source build needed)
log_info "Downloading dnscrypt-proxy ${DNSCRYPT_VERSION}"
DNSCRYPT_URL="https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/${DNSCRYPT_VERSION}/dnscrypt-proxy-linux_arm-${DNSCRYPT_VERSION}.tar.gz"
if ! curl -fsSL -o "${DOWNLOAD_DIR}/dnscrypt-proxy.tar.gz" "${DNSCRYPT_URL}"; then
    if is_service_enabled "dnscrypt_proxy" 2>/dev/null; then
        die "Failed to download dnscrypt-proxy, which is enabled in the current profile."
    else
        log_warn "Failed to download dnscrypt-proxy, but it is not enabled. Continuing."
    fi
fi

# Download Pi-hole FTL source and dependencies for compilation
log_info "Downloading Pi-hole FTL ${PIHOLE_VERSION} source"
if [ ! -f "${DOWNLOAD_DIR}/pihole-ftl-${PIHOLE_VERSION}.tar.gz" ]; then
    FTL_URL="https://github.com/pi-hole/pi-hole/archive/refs/tags/v${PIHOLE_VERSION}.tar.gz"
    if ! curl -fsSL -o "${DOWNLOAD_DIR}/pihole-ftl-${PIHOLE_VERSION}.tar.gz" "${FTL_URL}"; then
        if is_service_enabled "pihole" 2>/dev/null; then
            die "Failed to download pihole-FTL source, which is enabled in the current profile."
        else
            log_warn "Failed to download pihole-FTL source, but it is not enabled. Continuing."
        fi
    fi
fi

# Extract Pi-hole if downloaded
SHARED_ANSIBLE_DIR="${WORKSPACE_DIR:-/workspace}/shared/ansible"
if [ -f "${DOWNLOAD_DIR}/pihole-ftl-${PIHOLE_VERSION}.tar.gz" ]; then
    log_info "Extracting Pi-hole FTL source"
    cd "${DOWNLOAD_DIR}"
    tar -xzf "${DOWNLOAD_DIR}/pihole-ftl-${PIHOLE_VERSION}.tar.gz" 2>&1 || true
    if [ -d "${DOWNLOAD_DIR}/pi-hole-${PIHOLE_VERSION}" ] && [ ! -d "${SHARED_ANSIBLE_DIR}/playbooks/files/pi-hole-${PIHOLE_VERSION}" ]; then
        sudo mkdir -p "${SHARED_ANSIBLE_DIR}/playbooks/files/"
        sudo mv -f "${DOWNLOAD_DIR}/pi-hole-${PIHOLE_VERSION}" "${SHARED_ANSIBLE_DIR}/playbooks/files/pi-hole-${PIHOLE_VERSION}" || true
    fi
    cd "$WORK_DIR"
fi

# Copy downloads into chroot for Ansible to find
log_info "Copying downloads into chroot"
sudo mkdir -p "${MOUNT_POINT}/tmp/pimeleon-downloads"
sudo cp -r "${DOWNLOAD_DIR}"/* "${MOUNT_POINT}/tmp/pimeleon-downloads/" 2>/dev/null || true
sudo chmod -R 755 "${MOUNT_POINT}/tmp/pimeleon-downloads"

# Install ngrok (for remote access tunneling)
log_info "Downloading ngrok"
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc 2>&1 | chroot_run "${MOUNT_POINT}" tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com bookworm main" 2>&1 | chroot_run "${MOUNT_POINT}" tee /etc/apt/sources.list.d/ngrok.list
log_info "Installing ngrok for remote access tunneling"
chroot_run "${MOUNT_POINT}" apt-get -q update
chroot_run "${MOUNT_POINT}" apt-get -qy install ngrok

# =============================================================================
# Clone and build Pimeleon Web UI from GitLab
# =============================================================================
log_info "Building Pimeleon Web UI from GitLab..."

# Configurable via environment variables (see docker-compose.yml)
PIMELEON_UI_REPO="${PIMELEON_UI_REPO:-https://gitlab.pimeleon.dev/pimeleon/pimeleon-ui.git}"

# Branch: env var takes precedence, otherwise select based on profile
if [[ -n "${PIMELEON_UI_BRANCH:-}" ]]; then
    # Use explicitly configured branch
    :
elif [[ "${PIMELEON_PROFILE:-development}" == "development" ]]; then
    PIMELEON_UI_BRANCH="develop"
else
    PIMELEON_UI_BRANCH="master"
fi

PIMELEON_UI_BUILD_DIR="${CACHE_DIR}/pimeleon-ui"

# Ensure build directory is writable (CI cache may be root-owned)
sudo mkdir -p "${PIMELEON_UI_BUILD_DIR}"
sudo chown "$(id -u):$(id -g)" "${PIMELEON_UI_BUILD_DIR}"

# Construct authenticated URL if token is available
if [[ -n "${PIMELEON_UI_BUILD_TOKEN:-}" ]]; then
    PIMELEON_UI_REPO_AUTH=$(echo "${PIMELEON_UI_REPO}" | sed "s|https://|https://oauth2:${PIMELEON_UI_BUILD_TOKEN}@|")
else
    PIMELEON_UI_REPO_AUTH="${PIMELEON_UI_REPO}"
fi

# Clone or update repo
if [[ -d "${PIMELEON_UI_BUILD_DIR}/.git" ]]; then
    log_info "Updating existing pimeleon-ui clone..."
    git -C "${PIMELEON_UI_BUILD_DIR}" fetch origin
    git -C "${PIMELEON_UI_BUILD_DIR}" checkout "${PIMELEON_UI_BRANCH}"
    git -C "${PIMELEON_UI_BUILD_DIR}" reset --hard "origin/${PIMELEON_UI_BRANCH}"
else
    log_info "Cloning pimeleon-ui from ${PIMELEON_UI_REPO} (branch: ${PIMELEON_UI_BRANCH})..."
    git clone --depth 1 --branch "${PIMELEON_UI_BRANCH}" "${PIMELEON_UI_REPO_AUTH}" "${PIMELEON_UI_BUILD_DIR}"
fi

# Build UI and API using pnpm (Node.js 22 installed in builder image)
log_info "Building Pimeleon UI and API (${PIMELEON_PROFILE:-development} mode, branch: ${PIMELEON_UI_BRANCH})..."
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
pushd "${PIMELEON_UI_BUILD_DIR}" > /dev/null
NODE_ENV="${PIMELEON_PROFILE:-development}" pnpm install --frozen-lockfile
NODE_ENV="${PIMELEON_PROFILE:-development}" pnpm build
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

# Destination paths inside chroot image
PIMELEON_API_DEST="${MOUNT_POINT}/opt/pimeleon/api"
PIMELEON_PROXY_DEST="${MOUNT_POINT}/opt/pimeleon/proxy"
PIMELEON_UI_DEST="${MOUNT_POINT}/opt/pimeleon/ui"

# Copy FastAPI server if available
if [[ -d "${PIMELEON_API_SRC}" ]] && [[ -f "${PIMELEON_API_SRC}/requirements.txt" ]]; then
    log_info "Copying Pimeleon Python FastAPI server files"
    sudo mkdir -p "${PIMELEON_API_DEST}"
    sudo rsync -a --exclude '__pycache__' --exclude '*.pyc' --exclude 'logs' --exclude 'venv' --exclude '.env' --exclude '.env.example' "${PIMELEON_API_SRC}/" "${PIMELEON_API_DEST}/"
    log_info "Python FastAPI server copied: $(du -sh "${PIMELEON_API_DEST}" | cut -f1)"
else
    log_warn "Python FastAPI server not found at ${PIMELEON_API_SRC}, skipping"
fi

# Copy Nitro proxy if available
if [[ -d "${PIMELEON_PROXY_SRC}" ]] && [[ -f "${PIMELEON_PROXY_SRC}/index.mjs" ]]; then
    log_info "Copying pre-built Pimeleon Nuxt proxy files"
    sudo mkdir -p "${PIMELEON_PROXY_DEST}"
    sudo rsync -a --exclude 'node_modules' --exclude '.nuxt' --exclude 'logs' "${PIMELEON_PROXY_SRC}/" "${PIMELEON_PROXY_DEST}/"
    log_info "Nitro proxy copied: $(du -sh "${PIMELEON_PROXY_DEST}" | cut -f1)"
else
    log_warn "Nitro proxy not found at ${PIMELEON_PROXY_SRC}, skipping"
fi

# Copy Quasar SPA if available
if [[ -d "${PIMELEON_UI_SRC}" ]] && [[ -f "${PIMELEON_UI_SRC}/index.html" ]]; then
    log_info "Copying pre-built Pimeleon Quasar UI files"
    sudo mkdir -p "${PIMELEON_UI_DEST}"
    sudo rsync -a --exclude 'node_modules' --exclude '.quasar' --exclude 'logs' "${PIMELEON_UI_SRC}/" "${PIMELEON_UI_DEST}/"
    log_info "Quasar SPA copied: $(du -sh "${PIMELEON_UI_DEST}" | cut -f1)"
else
    log_warn "Quasar SPA not found at ${PIMELEON_UI_SRC}, skipping"
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
if [[ -d "${PLAYBOOKS_DIR}" ]] && [[ -n "$(ls -A ${PLAYBOOKS_DIR}/*.yml 2>/dev/null)" ]]; then
    log_info "Applying Ansible playbooks (Monorepo mode)"
    log_info "App: ${PIMELEON_APP:-not set}"
    export ANSIBLE_CONFIG="${SHARED_ANSIBLE_DIR}/ansible.cfg"
    export ANSIBLE_HOST_KEY_CHECKING=False
    export PYTHONUNBUFFERED=1

    # Determine platform group from environment (3B+ -> raspberrypi_3bplus, 4B -> raspberrypi_4b)
    PLATFORM_GROUP="raspberrypi_$(echo ${PIMELEON_RPI_MODEL:-3B+} | tr '[:upper:]' '[:lower:]' | tr -d '+')"
    log_info "Platform group: ${PLATFORM_GROUP}"

    # Create temporary inventory with platform group membership
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

    # Setup group_vars directory structure for Ansible
    mkdir -p "${WORK_DIR}/group_vars/all"
    mkdir -p "${WORK_DIR}/group_vars/raspberrypi"
    mkdir -p "${WORK_DIR}/group_vars/${PLATFORM_GROUP}"

    # Layer 1: Copy shared common vars (lowest priority)
    if [[ -d "${SHARED_VARS_DIR}/common" ]]; then
        log_info "Loading shared common vars from: ${SHARED_VARS_DIR}/common"
        cp -r "${SHARED_VARS_DIR}/common/"* "${WORK_DIR}/group_vars/all/" 2>/dev/null || true
    fi

    # Layer 2: Copy platform vars (raspberrypi family)
    if [[ -d "${SHARED_VARS_DIR}/platform/raspberrypi" ]]; then
        log_info "Loading platform vars from: ${SHARED_VARS_DIR}/platform/raspberrypi"
        cp -r "${SHARED_VARS_DIR}/platform/raspberrypi/"* "${WORK_DIR}/group_vars/raspberrypi/" 2>/dev/null || true
    fi

    # Layer 3: Copy app-specific vars (highest priority - overrides shared)
    APP_VARS_DIR="${WORKSPACE_DIR:-/workspace}/apps/${PIMELEON_APP}/vars"
    if [[ -d "${APP_VARS_DIR}" ]]; then
        log_info "Loading app-specific vars from: ${APP_VARS_DIR}"
        cp -r "${APP_VARS_DIR}/"* "${WORK_DIR}/group_vars/${PLATFORM_GROUP}/" 2>/dev/null || true
    fi

    # Copy profile vars to all group
    if [[ -f "${SHARED_VARS_DIR}/common/profiles/${PIMELEON_PROFILE:-development}.yml" ]]; then
        cp "${SHARED_VARS_DIR}/common/profiles/${PIMELEON_PROFILE:-development}.yml" "${WORK_DIR}/group_vars/all/profile.yml"
        log_info "Using profile: ${PIMELEON_PROFILE:-development}"
    fi

    # Run playbooks with platform, version, app, and profile extra-vars
    for playbook in ${PLAYBOOKS_DIR}/*.yml; do
        log_info "Running playbook: $(basename $playbook)"
        sudo -E ansible-playbook -v \
            -i "${WORK_DIR}/inventory" \
            --extra-vars "platform_model=${PIMELEON_RPI_MODEL:-3B+}" \
            --extra-vars "debian_version=${RASPBIAN_VERSION:-bookworm}" \
            --extra-vars "pimeleon_profile=${PIMELEON_PROFILE:-development}" \
            --extra-vars "pimeleon_app=${PIMELEON_APP:-}" \
            --extra-vars "pimeleon_initial_password=${PIMELEON_INITIAL_PASSWORD:-netblox}" \
            --extra-vars "pimeleon_ap_name=${PIMELEON_AP_NAME:-Pimeleon}" \
            "$playbook" 2>&1 | sudo tee -a "${ANSIBLE_LOG_FILE}" || die "Playbook failed: $playbook. See ${ANSIBLE_LOG_FILE} for details."
    done
else
    log_warn "No Ansible playbooks found at: ${PLAYBOOKS_DIR}"
fi

# Copy custom configs if available
if [[ -d "${CONFIG_DIR}" ]]; then
    log_info "Copying custom configurations"

    # Network configs
    if [[ -d "${CONFIG_DIR}/network" ]] && [[ -n "$(ls -A ${CONFIG_DIR}/network/* 2>/dev/null)" ]]; then
        sudo cp -r "${CONFIG_DIR}/network/"* "${MOUNT_POINT}/etc/network/" || true
    fi

    # Security configs
    if [[ -d "${CONFIG_DIR}/security" ]] && [[ -n "$(ls -A ${CONFIG_DIR}/security/* 2>/dev/null)" ]]; then
        sudo cp -r "${CONFIG_DIR}/security/"* "${MOUNT_POINT}/etc/" || true
    fi

    # Service configs
    if [[ -d "${CONFIG_DIR}/services" ]] && [[ -n "$(ls -A ${CONFIG_DIR}/services/* 2>/dev/null)" ]]; then
        sudo cp -r "${CONFIG_DIR}/services/"* "${MOUNT_POINT}/etc/" || true
    fi
fi

# Clean up APT cache configuration from final image
if [[ -f "${MOUNT_POINT}/etc/apt/apt.conf.d/01proxy" ]]; then
    log_info "Removing APT cache configuration from final image"
    sudo rm -f "${MOUNT_POINT}/etc/apt/apt.conf.d/01proxy"
fi

# Configure static resolv.conf for production (BIND9 handles DNS)
# This must be done AFTER all network operations (git clone, apt, etc.)
log_info "Configuring static DNS resolver for production"
cat > /tmp/resolv.conf <<EOF
# Static DNS configuration - BIND9 on localhost
nameserver 127.0.0.1
options edns0 trust-ad
EOF
sudo cp /tmp/resolv.conf "${MOUNT_POINT}/etc/resolv.conf"
sudo chmod 644 "${MOUNT_POINT}/etc/resolv.conf"

# Cleanup chroot
cleanup_chroot "${MOUNT_POINT}"

# Unmount image (includes boot partition)
unmount_image "${MOUNT_POINT}" "${LOOP_DEVICE}"

log_info "Stage 2 completed successfully"

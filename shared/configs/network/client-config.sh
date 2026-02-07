#!/bin/bash
# APT Cache Client Configuration Script for Pimeleon Network
# This script configures any Debian-based system to use the APT cache

set -e

# Configuration
CACHE_SERVER="192.168.76.5"  # TrueNAS IP (use IP for Docker containers)
CACHE_PORT="3142"
PROXY_URL="http://${CACHE_SERVER}:${CACHE_PORT}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_msg() {
    echo -e "${2}${1}${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_msg "This script must be run as root (use sudo)" "$RED"
   exit 1
fi

# Detect distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION=$VERSION_ID
else
    print_msg "Cannot detect distribution" "$RED"
    exit 1
fi

print_msg "=== APT Cache Configuration for Pimeleon Network ===" "$GREEN"
print_msg "Detected: $DISTRO $VERSION" "$YELLOW"
print_msg "Cache Server: $PROXY_URL" "$YELLOW"

# Function to test cache connectivity
test_cache() {
    print_msg "\nTesting cache server connectivity..." "$YELLOW"
    if wget -q --spider "${PROXY_URL}/acng-report.html" 2>/dev/null; then
        print_msg "✓ Cache server is reachable" "$GREEN"
        return 0
    else
        print_msg "✗ Cannot reach cache server at $PROXY_URL" "$RED"
        return 1
    fi
}

# Function to configure APT proxy
configure_apt() {
    local apt_conf_dir="/etc/apt/apt.conf.d"
    local proxy_conf="${apt_conf_dir}/02proxy"

    print_msg "\nConfiguring APT to use cache..." "$YELLOW"

    # Backup existing configuration
    if [ -f "$proxy_conf" ]; then
        cp "$proxy_conf" "${proxy_conf}.backup.$(date +%Y%m%d_%H%M%S)"
        print_msg "Backed up existing configuration" "$YELLOW"
    fi

    # Create proxy configuration
    cat > "$proxy_conf" << EOF
# APT Cacher NG Proxy Configuration - Pimeleon Network
# Generated: $(date)
# Cache Server: $CACHE_SERVER

Acquire::http::Proxy "${PROXY_URL}";

# Bypass proxy for local repositories
Acquire::http::Proxy::localhost "DIRECT";
Acquire::http::Proxy::127.0.0.1 "DIRECT";
Acquire::http::Proxy::${CACHE_SERVER} "DIRECT";

# Connection settings
Acquire::http::Timeout "30";
Acquire::http::ConnectionAttemptDelayMsec "500";
Acquire::http::Pipeline-Depth "5";

# Cache-specific headers
Acquire::http::User-Agent "Pimeleon-Client/1.0";
EOF

    print_msg "✓ APT proxy configuration created" "$GREEN"
}

# Function to configure for Raspberry Pi
configure_raspbian() {
    if [ "$DISTRO" = "raspbian" ] || [ -f /etc/rpi-issue ]; then
        print_msg "\nDetected Raspberry Pi - applying specific configuration..." "$YELLOW"

        # Ensure Raspberry Pi archive is also proxied
        local rpi_list="/etc/apt/sources.list.d/raspi.list"
        if [ -f "$rpi_list" ]; then
            print_msg "✓ Raspberry Pi repositories will use cache" "$GREEN"
        fi
    fi
}

# Function to test configuration
test_configuration() {
    print_msg "\nTesting APT configuration..." "$YELLOW"

    # Update package lists through cache
    if apt-get update 2>&1 | grep -q "Hit:.*${CACHE_SERVER}"; then
        print_msg "✓ APT is successfully using the cache" "$GREEN"
        return 0
    else
        print_msg "⚠ APT may not be using the cache correctly" "$YELLOW"
        return 1
    fi
}

# Function to show cache statistics
show_stats() {
    print_msg "\nCache Statistics:" "$YELLOW"
    local stats_url="${PROXY_URL}/acng-report.html"

    if command -v curl &> /dev/null; then
        curl -s "$stats_url" | grep -E "Total|Hit|Miss|Data" | head -5 || true
    else
        print_msg "Install curl to view cache statistics" "$YELLOW"
    fi
}

# Function to remove configuration
remove_configuration() {
    print_msg "\nRemoving APT cache configuration..." "$YELLOW"

    local proxy_conf="/etc/apt/apt.conf.d/02proxy"
    if [ -f "$proxy_conf" ]; then
        rm "$proxy_conf"
        print_msg "✓ Configuration removed" "$GREEN"
    else
        print_msg "No configuration found" "$YELLOW"
    fi
}

# Function for Pimeleon auto-discovery setup
setup_autodiscovery() {
    print_msg "\nSetting up auto-discovery for Pimeleon network..." "$YELLOW"

    # Create systemd service for DHCP option injection
    cat > /etc/systemd/system/apt-cache-announce.service << EOF
[Unit]
Description=Announce APT Cache via DHCP
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/echo "APT Cache available at ${PROXY_URL}"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    print_msg "✓ Auto-discovery service created" "$GREEN"
}

# Main menu
show_menu() {
    echo
    print_msg "=== Pimeleon APT Cache Configuration ===" "$GREEN"
    echo "1) Configure this system to use cache"
    echo "2) Test cache connectivity"
    echo "3) Show cache statistics"
    echo "4) Remove cache configuration"
    echo "5) Setup auto-discovery (Pimeleon only)"
    echo "6) Exit"
    echo
    read -p "Select option: " choice

    case $choice in
        1)
            test_cache && configure_apt && configure_raspbian && test_configuration
            print_msg "\n✓ Configuration complete!" "$GREEN"
            print_msg "Your system will now use the APT cache at $PROXY_URL" "$YELLOW"
            ;;
        2)
            test_cache
            ;;
        3)
            show_stats
            ;;
        4)
            remove_configuration
            ;;
        5)
            setup_autodiscovery
            ;;
        6)
            exit 0
            ;;
        *)
            print_msg "Invalid option" "$RED"
            ;;
    esac
}

# Command line arguments
if [ "$1" = "--auto" ]; then
    # Automatic configuration
    test_cache && configure_apt && configure_raspbian && test_configuration
    print_msg "\n✓ Automatic configuration complete!" "$GREEN"
elif [ "$1" = "--remove" ]; then
    remove_configuration
elif [ "$1" = "--test" ]; then
    test_cache && test_configuration
elif [ "$1" = "--help" ]; then
    echo "Usage: $0 [OPTION]"
    echo "Configure APT to use Pimeleon cache server"
    echo
    echo "Options:"
    echo "  --auto    Configure automatically"
    echo "  --remove  Remove configuration"
    echo "  --test    Test cache connectivity"
    echo "  --help    Show this help"
    echo
    echo "Without options, shows interactive menu"
else
    # Interactive menu
    while true; do
        show_menu
    done
fi

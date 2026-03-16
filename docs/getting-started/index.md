# Getting Started

Welcome to the Pimeleon Build System! This guide will help you build your first
custom Raspberry Pi router image in just a few minutes.

## What You'll Build

By following this guide, you'll create a **bootable 4GB SD card image** for Raspberry Pi 3B+ with:

- :material-router-wireless: **Router functionality** - WAN/LAN routing with NAT
- :material-wifi: **WiFi Access Point** - Pre-configured hostapd
- :material-shield-check: **Security hardening** - SSH, firewall, fail2ban
- :material-network: **Network services** - DHCP, DNS, systemd-networkd
- :material-update: **Automatic updates** - Unattended security updates

## Prerequisites

Before you begin, make sure you have:

- [x] Docker 24.0+ with BuildKit support
- [x] 50GB+ free disk space
- [x] 8GB+ RAM (16GB recommended)
- [x] Linux host with ARM binary format support
- [x] Basic familiarity with Docker and command line

!!! tip "Quick prerequisite check"
    ```bash
    # Check Docker version
    docker --version  # Should be 24.0 or higher

    # Check available space
    df -h /var/lib/docker  # Should show 50GB+ available

    # Check memory
    free -h  # Should show 8GB+ total
    ```

For detailed prerequisite installation, see [Prerequisites](prerequisites.md).

## Quick Start

### Step 1: Install Prerequisites

Install ARM binary format support on your Linux host:

```bash
sudo apt update
sudo apt install binfmt-support qemu-user-static
```text

Verify ARM emulation is working:

```bash
ls -la /proc/sys/fs/binfmt_misc/qemu-arm
# Should show a file exists
```text

### Step 2: Clone the Repository

```bash
git clone https://github.com/yourusername/pimeleon.git
cd pimeleon
```text

### Step 3: Build Containers

Build the Docker containers (one-time setup):

```bash
export DOCKER_BUILDKIT=1
docker compose build
```text

!!! info "Build time"
    First container build takes 5-10 minutes. Subsequent builds use Docker layer cache.

### Step 4: Create Your First Image

Run the builder to create a Pimeleon image:

=== "With APT Cache (Recommended)"

    If you have an APT caching proxy (like apt-cacher-ng):

    ```bash
    export DOCKER_BUILDKIT=1
    export APT_PROXY=192.168.76.5:3142    # Your cache server (host:port)
    export RASPBIAN_MIRROR=http://archive.raspbian.org/raspbian/

    docker compose run --rm builder
    ```

    **Build time: ~10 minutes** (with cache hits)

=== "Without APT Cache"

    Direct download from Raspbian archive:

    ```bash
    export DOCKER_BUILDKIT=1
    export RASPBIAN_MIRROR=http://mirrordirector.raspbian.org/raspbian/

    docker compose run --rm builder
    ```

    **Build time: ~20 minutes** (downloading packages)

=== "Using Makefile"

    Simplified command using Make:

    ```bash
    make build
    ```

    The Makefile automatically sets required environment variables.

### Step 5: Find Your Image

Your built image will be in the `output/` directory:

```bash
ls -lh output/
```text

You'll see:

```text
pimeleon-20241102-103045.img      # 4GB bootable image
pimeleon-20241102-103045.img.sha256  # Checksum
build-20241102-103045.log          # Build log
pi-initial-password.txt            # Generated password for 'pi' user
```text

### Step 6: Flash to SD Card

Flash the image to a microSD card (8GB minimum):

=== "Linux"

    ```bash
    # Find your SD card device (e.g., /dev/sdb)
    lsblk

    # Flash the image (replace /dev/sdX with your SD card)
    sudo dd if=output/pimeleon-*.img of=/dev/sdX bs=4M status=progress conv=fsync

    # Sync to ensure all data is written
    sync
    ```

=== "macOS"

    ```bash
    # Find your SD card device
    diskutil list

    # Unmount the SD card (replace N with disk number)
    diskutil unmountDisk /dev/diskN

    # Flash the image
    sudo dd if=output/pimeleon-*.img of=/dev/rdiskN bs=4m

    # Eject the SD card
    diskutil eject /dev/diskN
    ```

=== "Windows"

    Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) or [balenaEtcher](https://www.balena.io/etcher/):

    1. Select "Use custom" image
    2. Choose your `pimeleon-*.img` file
    3. Select your SD card
    4. Click "Write"

!!! warning "Data Loss Warning"
    Double-check the device name! `dd` will overwrite all data on the target device.

### Step 7: Boot Your Pimeleon

1. Insert the SD card into your Raspberry Pi 3B+
2. Connect:
   - **eth0** - WAN connection (to your internet modem/router)
   - **eth1** - LAN connection (to your local network) OR
   - **wlan0** - WiFi clients can connect to SSID "pimeleon"
3. Power on the Pi
4. Wait 1-2 minutes for first boot

### Step 8: Access Your Pimeleon

Once booted, access via SSH:

```bash
# Via management interface (if configured)
ssh pi@172.16.0.1

# Via LAN interface
ssh pi@192.168.42.1

# Via WiFi AP interface
ssh pi@192.168.42.1
```

Use the SSH key you configured during build, or the password from `output/pi-initial-password.txt`.

## What's Next?

<div class="grid cards" markdown>

- :material-file-document-edit:{ .lg .middle } **Customize Your Build**

    ---

    Learn how to customize network configuration, packages, and security settings

    [:octicons-arrow-right-24: Customization Guide](../guides/customization.md)

- :material-speedometer:{ .lg .middle } **Optimize Performance**

    ---

    Set up caching, enable build stages, and reduce build times

    [:octicons-arrow-right-24: Performance Guide](../guides/performance.md)

- :material-bug:{ .lg .middle } **Troubleshooting**

    ---

    Common issues and solutions for build problems

    [:octicons-arrow-right-24: Troubleshooting](../guides/troubleshooting.md)

- :material-book-open-variant:{ .lg .middle } **Deep Dive**

    ---

    Understand the architecture and build pipeline

    [:octicons-arrow-right-24: Architecture](../architecture/overview.md)

</div>

## Build Options

### Environment Variables

Customize your build with environment variables:

```bash
# Required
export DOCKER_BUILDKIT=1                    # Enable BuildKit

# Target hardware
export PIMELEON_RPI_MODEL=3B+               # Pi model (3B+, 4, Zero W)
export PIMELEON_IMAGE_SIZE=4G               # Image size (4G, 8G)

# Network optimization
export APT_PROXY=192.168.76.5:3142          # APT cache proxy (host:port)
export RASPBIAN_MIRROR=http://mirrordirector.raspbian.org/raspbian/

# Customization
export PIMELEON_INITIAL_PASSWORD=mypassword  # Custom password
```text

See [Environment Variables Reference](../reference/environment-variables.md) for complete list.

### Make Targets

Use Makefile for common tasks:

```bash
make build              # Build image
make build-nocache      # Build without Docker cache
make test               # Run test suite
make test-smoke         # Quick smoke test
make clean              # Clean build artifacts
make shell              # Open builder shell for debugging
```text

See [CLI Commands](../reference/cli-commands.md) for complete reference.

## Getting Help

- **Documentation**: You're reading it! Use the search bar above
- **Common Issues**: Check [Troubleshooting Guide](../guides/troubleshooting.md)
- **Bug Reports**: [GitHub Issues](https://github.com/yourusername/pimeleon/issues)
- **Feature Requests**: [GitHub Discussions](https://github.com/yourusername/pimeleon/discussions)

## Summary

✅ You've successfully built a custom Raspberry Pi router image!
✅ You know how to flash it to an SD card
✅ You can access your Pimeleon via SSH

Now explore the guides to customize and optimize your builds!

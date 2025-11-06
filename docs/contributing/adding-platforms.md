# Contributing a New Platform

## Overview

Thank you for your interest in adding support for a new ARM platform to Pi Router! This guide will walk you through the process of contributing a new hardware platform.

**Target Audience**: Community members who want to add support for new ARM single-board computers (Orange Pi, Rock Pi, Nano Pi, etc.)

**Prerequisites**:
- Familiarity with the target hardware
- Basic understanding of Linux boot process
- Git and Docker knowledge
- Access to the physical hardware (recommended for testing)

## Platform Contribution Checklist

Before submitting your platform contribution, ensure you have completed:

- [ ] Hardware profile YAML created and validates
- [ ] Profile tested with successful image build
- [ ] Platform-specific documentation written
- [ ] Platform boots successfully (QEMU or real hardware)
- [ ] Tests created and passing
- [ ] PR submitted with all requirements

---

## Step-by-Step Guide

### Step 1: Research Your Platform

Before creating a profile, gather the following information about your target hardware:

#### Hardware Specifications
- **SoC (System-on-Chip)**: Model number (e.g., RK3588, Allwinner H6)
- **CPU Architecture**: armhf (32-bit) or arm64 (64-bit)
- **RAM**: Available memory sizes
- **Storage Interface**: SD card, eMMC, NVMe, SATA
- **Network**: Ethernet speed, WiFi chip, Bluetooth

#### Boot Requirements
- **Bootloader**: U-Boot, vendor firmware, or other
- **Device Tree**: DTB filename and source location
- **Boot Partition**: Size and filesystem type required
- **Boot Configuration**: Scripts or config files needed

#### Operating System
- **Recommended Distribution**: Armbian, Debian, Ubuntu
- **Kernel**: Mainline, vendor, or Armbian kernel
- **Package Repository**: APT mirror URL
- **Firmware Packages**: Required firmware packages

#### References
- Hardware vendor documentation
- Community wiki (Armbian docs, manufacturer forums)
- Existing device tree sources
- Similar platform profiles in this project

**Example Research for Orange Pi 5 Plus**:
```
Hardware:
- SoC: Rockchip RK3588
- Architecture: ARM64 (aarch64)
- RAM: 4GB, 8GB, 16GB, 32GB variants
- Storage: eMMC (primary), SD card (secondary)
- Network: 2.5GbE + WiFi 6

Boot:
- Bootloader: U-Boot 2023.04+
- Device Tree: rk3588-orangepi-5-plus.dtb
- Boot Partition: 512MB ext4
- Boot Script: boot.scr (mkimage format)

OS:
- Distribution: Armbian or Debian Bookworm
- Kernel: linux-image-current-rockchip-rk3588
- Repository: http://apt.armbian.com/
- Firmware: firmware-realtek (WiFi)
```

---

### Step 2: Set Up Development Environment

1. **Fork and clone the repository**:
   ```bash
   git clone https://github.com/yourusername/pi-router-build.git
   cd pi-router-build
   ```

2. **Create a feature branch**:
   ```bash
   git checkout -b platform/orangepi-5plus
   ```

3. **Install dependencies**:
   ```bash
   # Ensure Docker and Docker Compose installed
   docker --version
   docker compose version

   # Install yq for YAML validation
   wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
   chmod +x /usr/local/bin/yq
   ```

---

### Step 3: Create Platform Structure

1. **Create platform directories**:
   ```bash
   mkdir -p platforms/orangepi/{profiles,hooks,tests,docs}
   ```

2. **Copy template files**:
   ```bash
   # Use Raspberry Pi as reference template
   cp platforms/raspberrypi/profiles/3b-plus.yaml \
      platforms/orangepi/profiles/5-plus.yaml
   ```

---

### Step 4: Create Hardware Profile

Edit your profile YAML file with platform-specific values.

**File**: `platforms/orangepi/profiles/5-plus.yaml`

```yaml
# Metadata
metadata:
  platform: orangepi              # Platform identifier (lowercase, no spaces)
  model: 5-plus                   # Model identifier (matches filename)
  display_name: "Orange Pi 5 Plus"
  vendor: Shenzhen Xunlong Software
  maintainer: yourusername        # Your GitHub username
  status: experimental            # experimental → beta → stable
  documentation_url: http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/details/Orange-Pi-5-plus.html

# Hardware specifications
hardware:
  architecture: arm64             # armhf or arm64
  soc: RK3588
  cpu_cores: 8
  cpu_freq_mhz: 2400
  ram_mb: 16384                   # For 16GB variant
  storage_interface: emmc         # sdcard, emmc, nvme, sata

  # Network capabilities
  network:
    ethernet: true
    ethernet_speed_mbps: 2500     # 2.5 Gigabit Ethernet
    wifi: true
    wifi_chip: realtek-rtw89
    bluetooth: true

# Bootloader configuration
bootloader:
  type: u-boot                    # pi-firmware, u-boot, grub
  partition_type: ext4            # Filesystem for boot partition
  partition_size: 512M            # Boot partition size
  partition_label: boot

  # U-Boot specific files (if building from source)
  files:
    - u-boot.bin
    - trust.img

  # Boot script template (Jinja2)
  config_template: platforms/orangepi/templates/boot.scr.j2

  # Device tree blob
  device_tree: rk3588-orangepi-5-plus.dtb

# Operating system configuration
os:
  distribution: debian            # raspbian, debian, ubuntu, armbian
  version: bookworm               # Debian 12
  mirror: http://deb.debian.org/debian/
  architecture: arm64

  # Additional repositories
  additional_repos:
    - name: armbian
      url: http://apt.armbian.com/
      key_url: http://apt.armbian.com/armbian.key
      components: main bookworm-utils

# Package configuration
packages:
  # Kernel package
  kernel: linux-image-current-rockchip-rk3588

  # Firmware packages
  firmware:
    - firmware-realtek            # WiFi firmware
    - armbian-firmware            # Additional firmware

  # Platform-specific utilities
  utilities:
    - orangepi-config             # If available

  # Additional packages
  additional:
    - network-manager
    - wireless-tools

# Storage configuration
storage:
  device: mmcblk1                 # eMMC is typically mmcblk1 (SD is mmcblk0)
  root_partition_suffix: p2       # Root: /dev/mmcblk1p2
  boot_partition_suffix: p1       # Boot: /dev/mmcblk1p1

  # Filesystem types
  boot_fs: ext4
  root_fs: ext4

# Hardware features
features:
  uart: true                      # Serial console
  spi: false                      # SPI bus (if available)
  i2c: false                      # I2C bus (if available)
  gpio: true                      # GPIO pins

  # Hardware-specific groups
  hardware_groups:
    - gpio
    - dialout                     # For UART access

# Network configuration defaults
network:
  wan_interface: eth0             # Primary ethernet
  lan_interface: wlan0            # WiFi for LAN (if used)
  mgmt_interface: eth0:0
  mgmt_ip: 172.16.0.1
  mgmt_netmask: 255.255.255.0

# Testing configuration
testing:
  # QEMU machine type (if supported)
  qemu_machine: virt              # Generic ARM64 virt machine

  # Expected boot time
  expected_boot_time: 90          # Seconds

  # Required tests
  required_tests:
    - boot
    - network

# Build configuration
build:
  cache_version: 1                # Increment to invalidate cache
  expected_build_time: 15         # Minutes
  parallel_jobs: 8                # For make -j
  compression: xz                 # xz, gzip, bzip2, none
```

---

### Step 5: Create Boot Configuration Template

#### For U-Boot Platforms

**File**: `platforms/orangepi/templates/boot.scr.j2`

```bash
# Orange Pi {{ HW_MODEL }} U-Boot Boot Script
# Generated by pi-router-build

# Set console
setenv console "console=ttyS2,1500000"

# Set boot device
setenv bootdev "mmc 1"  # eMMC is mmc 1, SD card is mmc 0

# Set boot arguments
setenv bootargs "${console} root=/dev/{{ STORAGE_DEVICE }}{{ STORAGE_ROOT_SUFFIX }} rootfstype={{ STORAGE_ROOT_FS }} rootwait rw"

# Load kernel, device tree, and initramfs
load ${bootdev}:1 ${kernel_addr_r} /vmlinuz
load ${bootdev}:1 ${fdt_addr_r} /dtb/rockchip/{{ BOOT_DEVICE_TREE }}
load ${bootdev}:1 ${ramdisk_addr_r} /initrd.img

# Set device tree
fdt addr ${fdt_addr_r}
fdt resize

# Boot kernel
booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}
```

**Compile boot script to boot.scr**:

This template will be rendered and compiled to `boot.scr` using `mkimage` during the build process.

#### For Pi Firmware Platforms

**File**: `platforms/yourplatform/templates/config.txt.j2`

```jinja2
# {{ HW_DISPLAY_NAME }} Configuration
# Generated by pi-router-build

# UART
enable_uart={{ 1 if FEATURES_UART == 'true' else 0 }}

# Hardware interfaces
dtparam=spi={{ 'on' if FEATURES_SPI == 'true' else 'off' }}
dtparam=i2c={{ 'on' if FEATURES_I2C == 'true' else 'off' }}

# Performance
{% if PERF_ARM_FREQ %}
arm_freq={{ PERF_ARM_FREQ }}
{% endif %}

# Device tree
dtoverlay=vc4-kms-v3d
```

---

### Step 6: Create Platform-Specific Hooks (Optional)

If your platform requires special build steps not covered by the standard pipeline, create hooks.

#### Available Hooks

- **pre-customize.sh**: Runs before stage 2 customization
- **post-customize.sh**: Runs after stage 2 customization
- **install-bootloader.sh**: Custom bootloader installation

#### Example: U-Boot Installation Hook

**File**: `platforms/orangepi/hooks/install-bootloader.sh`

```bash
#!/bin/bash
# Install U-Boot for Orange Pi 5 Plus

set -euo pipefail

install_bootloader() {
    local boot_mount="$1"
    local image_path="$2"

    log_info "Installing U-Boot for Orange Pi 5+"

    # Download pre-built U-Boot (or build from source)
    local uboot_url="https://github.com/armbian/build/releases/download/24.5.0/u-boot-orangepi5plus.deb"

    wget -O /tmp/u-boot.deb "${uboot_url}"

    # Extract U-Boot files
    dpkg -x /tmp/u-boot.deb /tmp/uboot

    # Copy U-Boot files to boot partition
    cp /tmp/uboot/usr/lib/u-boot/orangepi5plus/* "${boot_mount}/"

    # Write U-Boot to image (RK3588 specific offsets)
    dd if=/tmp/uboot/usr/lib/u-boot/orangepi5plus/idbloader.img \
       of="${image_path}" seek=64 conv=notrunc
    dd if=/tmp/uboot/usr/lib/u-boot/orangepi5plus/u-boot.itb \
       of="${image_path}" seek=16384 conv=notrunc

    log_info "U-Boot installed successfully"
}

# Export function for use by build script
export -f install_bootloader
```

**Hook Integration**:

The build system will automatically source and execute hooks if they exist:

```bash
# In build.sh
if [[ -f "platforms/${PLATFORM}/hooks/install-bootloader.sh" ]]; then
    source "platforms/${PLATFORM}/hooks/install-bootloader.sh"
    install_bootloader "${BOOT_MOUNT}" "${IMAGE_PATH}"
fi
```

---

### Step 7: Validate Profile

Use the validation script to check your profile:

```bash
# Validate YAML syntax and required fields
./scripts/validate-profile.sh platforms/orangepi/profiles/5-plus.yaml
```

**Expected output**:
```
Validating profile: platforms/orangepi/profiles/5-plus.yaml
✅ Profile validation passed
```

**Common validation errors**:

- **Invalid YAML syntax**: Use a YAML linter or online validator
- **Missing required fields**: Check against schema in [Hardware Profiles](../architecture/hardware-profiles.md)
- **Invalid enum values**: Ensure `architecture`, `bootloader.type`, etc. use valid values

---

### Step 8: Test Build Locally

Attempt to build your platform image locally:

```bash
# Set environment variables
export PIROUTER_PLATFORM=orangepi
export PIROUTER_MODEL=5-plus

# Build using Docker Compose
docker compose run --rm builder
```

**Monitor build progress**:

```bash
# In another terminal
tail -f output/build-*.log
```

**Common build issues**:

1. **Package not found**: Check package name and repository availability
   ```bash
   # Test package availability in chroot
   chroot_run apt-cache search linux-image
   ```

2. **Device tree not found**: Verify DTB path and kernel package contents
   ```bash
   # List available device trees
   ls mount/boot/*.dtb
   ls mount/boot/dtb/
   ```

3. **Bootloader installation fails**: Check hook script permissions and paths
   ```bash
   # Make hook executable
   chmod +x platforms/orangepi/hooks/install-bootloader.sh
   ```

4. **Template rendering errors**: Check Jinja2 syntax and variable names
   ```bash
   # Test template manually
   python3 scripts/render-template.py platforms/orangepi/templates/boot.scr.j2
   ```

**Expected build output**:

```
output/
├── pi-router-20250106-143022.img          # 4GB image file
├── build-20250106-143022.log              # Build log
└── orangepi-5-plus-bookworm-arm64-base-v1.tar.gz  # Cached base system
```

---

### Step 9: Test Image Boot

#### Option A: QEMU Testing (Recommended for Initial Testing)

```bash
# Install QEMU ARM64 emulation
sudo apt-get install qemu-system-arm qemu-efi-aarch64

# Boot image in QEMU
qemu-system-aarch64 \
  -M virt \
  -cpu cortex-a57 \
  -m 2048 \
  -nographic \
  -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
  -drive if=none,file=output/pi-router-*.img,format=raw,id=hd \
  -device virtio-blk-device,drive=hd \
  -netdev user,id=net0 \
  -device virtio-net-device,netdev=net0
```

**Expected behavior**:
- Kernel loads and boots
- Console output visible
- Network interfaces detected
- SSH service starts

**Abort boot test**: Press `Ctrl+A`, then `X`

#### Option B: Real Hardware Testing (Recommended for Final Validation)

1. **Flash image to SD card or eMMC**:
   ```bash
   # Find device
   lsblk

   # Flash image (replace /dev/sdX with your device)
   sudo dd if=output/pi-router-*.img of=/dev/sdX bs=4M status=progress
   sudo sync
   ```

2. **Boot hardware**:
   - Insert SD card / boot from eMMC
   - Connect serial console (UART)
   - Power on device

3. **Monitor boot**:
   ```bash
   # Connect via serial console
   sudo screen /dev/ttyUSB0 1500000

   # Or SSH after boot
   ssh pi@<device-ip>
   ```

4. **Verify functionality**:
   ```bash
   # Check kernel version
   uname -a

   # Check network interfaces
   ip addr show

   # Check hardware groups
   groups pi

   # Check services
   systemctl status systemd-networkd
   ```

**Document test results**:
```
Hardware: Orange Pi 5 Plus (16GB)
Storage: eMMC 64GB
Test Date: 2025-01-06

✅ Boot successful
✅ Serial console working
✅ Network interfaces detected (eth0, wlan0)
✅ SSH accessible
✅ GPIO groups created
⚠️  WiFi requires manual configuration (known issue)
```

---

### Step 10: Write Documentation

Create platform-specific documentation to help users.

**File**: `platforms/orangepi/README.md`

```markdown
# Orange Pi Support

## Supported Models

- **Orange Pi 5 Plus** - Status: Beta

## Hardware Requirements

- Orange Pi 5 Plus (any RAM variant)
- eMMC module or SD card (16GB minimum)
- Power supply (5V/4A recommended)
- Ethernet cable (for initial setup)

## Quick Start

### Building an Image

```bash
export PIROUTER_PLATFORM=orangepi
export PIROUTER_MODEL=5-plus
make build
```

### Flashing to eMMC

1. Boot from SD card with Armbian
2. Flash image to eMMC:
   ```bash
   sudo dd if=output/pi-router-*.img of=/dev/mmcblk1 bs=4M status=progress
   sudo sync
   ```
3. Reboot from eMMC

## Known Issues

- **WiFi**: Requires manual firmware installation (see Troubleshooting)
- **NVMe**: Not yet supported, use eMMC or SD card
- **HDMI**: Console output on HDMI not working, use serial console

## Troubleshooting

### WiFi Not Working

```bash
# Install Realtek firmware
sudo apt-get update
sudo apt-get install firmware-realtek
sudo reboot
```

### Serial Console Access

Connect UART adapter to pins:
- TX: Pin 8 (GPIO14)
- RX: Pin 10 (GPIO15)
- GND: Pin 6

Console settings: 1500000 baud, 8N1

```bash
screen /dev/ttyUSB0 1500000
```

## Performance

- **Build time**: ~15 minutes (with cache)
- **Boot time**: ~90 seconds
- **Network throughput**: 2.5 Gbps (ethernet)

## Contributing

Maintainer: @yourusername

Report issues: [GitHub Issues](https://github.com/yourorg/pi-router-build/issues)
```

---

### Step 11: Create Tests

Add platform-specific tests to ensure build quality.

**File**: `platforms/orangepi/tests/test_orangepi_5plus.py`

```python
import pytest
import yaml
from pathlib import Path

def test_profile_exists():
    """Test that Orange Pi 5+ profile exists"""
    profile = Path("platforms/orangepi/profiles/5-plus.yaml")
    assert profile.exists(), "Profile file not found"

def test_profile_valid():
    """Test that profile is valid YAML"""
    profile = Path("platforms/orangepi/profiles/5-plus.yaml")
    with open(profile) as f:
        data = yaml.safe_load(f)
        assert data is not None

def test_profile_metadata():
    """Test profile metadata fields"""
    profile = Path("platforms/orangepi/profiles/5-plus.yaml")
    with open(profile) as f:
        data = yaml.safe_load(f)

        assert data['metadata']['platform'] == 'orangepi'
        assert data['metadata']['model'] == '5-plus'
        assert data['metadata']['maintainer'] == 'yourusername'

def test_bootloader_config():
    """Test bootloader configuration"""
    profile = Path("platforms/orangepi/profiles/5-plus.yaml")
    with open(profile) as f:
        data = yaml.safe_load(f)

        assert data['bootloader']['type'] == 'u-boot'
        assert data['bootloader']['device_tree'] == 'rk3588-orangepi-5-plus.dtb'

def test_boot_template_exists():
    """Test that boot template exists"""
    template = Path("platforms/orangepi/templates/boot.scr.j2")
    assert template.exists(), "Boot template not found"

def test_hook_executable():
    """Test that hooks are executable"""
    hook = Path("platforms/orangepi/hooks/install-bootloader.sh")
    if hook.exists():
        assert hook.stat().st_mode & 0o111, "Hook not executable"
```

**Run tests**:

```bash
# Install pytest
pip3 install pytest pyyaml

# Run platform-specific tests
pytest platforms/orangepi/tests/

# Run all tests
pytest platforms/
```

---

### Step 12: Submit Pull Request

1. **Commit your changes**:
   ```bash
   git add platforms/orangepi/
   git commit -m "feat(platform): add Orange Pi 5 Plus support

   - Create Orange Pi 5+ hardware profile
   - Add U-Boot boot script template
   - Implement bootloader installation hook
   - Add platform documentation and tests
   - Tested on real hardware: boots successfully

   Closes #123"
   ```

2. **Push to your fork**:
   ```bash
   git push origin platform/orangepi-5plus
   ```

3. **Create pull request** on GitHub with:

   **Title**: `feat(platform): Add Orange Pi 5 Plus support`

   **Description**:
   ```markdown
   ## Platform Information

   - **Platform**: Orange Pi
   - **Model**: 5 Plus
   - **SoC**: Rockchip RK3588
   - **Architecture**: ARM64
   - **Status**: Beta

   ## Testing

   - [x] Profile validates successfully
   - [x] Image builds without errors
   - [x] Boots successfully in QEMU
   - [x] Boots successfully on real hardware
   - [x] Network interfaces working
   - [x] SSH accessible
   - [x] All tests passing

   ## Build Logs

   Build time: 14m 32s
   Image size: 3.8GB (uncompressed)
   Cache generated: orangepi-5-plus-bookworm-arm64-base-v1.tar.gz (186MB)

   ## Hardware Testing

   Tested on Orange Pi 5 Plus (16GB RAM, 64GB eMMC):
   - Boot time: ~87 seconds
   - Serial console: Working
   - Ethernet: Working (2.5GbE)
   - WiFi: Working (after firmware install)
   - SSH: Working

   ## Known Issues

   - WiFi requires manual firmware installation (documented)
   - NVMe support not yet implemented

   ## Maintainer Commitment

   I commit to maintaining this platform for at least 6 months, including:
   - Responding to issues within 2 weeks
   - Keeping profile up-to-date
   - Providing user support

   ## Checklist

   - [x] Profile created and validates
   - [x] Boot configuration template created
   - [x] Documentation written
   - [x] Tests created and passing
   - [x] Tested on real hardware
   - [x] Maintainer commitment made
   ```

4. **Respond to review feedback**:
   - Address reviewer comments
   - Update code as requested
   - Push additional commits to same branch
   - Re-request review when ready

---

## Platform Maintenance

Once your platform is merged, you'll be listed as the platform maintainer.

### Maintainer Responsibilities

1. **Issue Triage** (Weekly):
   - Review issues tagged with your platform
   - Reproduce and investigate bugs
   - Provide workarounds or fixes

2. **Updates** (Monthly):
   - Keep profile up-to-date with OS releases
   - Update kernel and firmware packages
   - Test with latest codebase

3. **User Support** (Ongoing):
   - Answer questions on GitHub discussions
   - Help users troubleshoot issues
   - Update documentation based on common questions

4. **Testing** (Per Release):
   - Test platform builds before releases
   - Report regressions
   - Validate new features work on your platform

### Getting Help

- **Slack/Discord**: Join #platform-maintainers channel
- **Discussions**: Ask in GitHub Discussions
- **Core Team**: Tag @core-team for urgent issues

---

## Platform Status Levels

### Experimental
- Initial submission
- Limited testing
- May have known issues
- Community support only

### Beta
- Proven to work on real hardware
- Documentation complete
- Regular testing
- Core team + maintainer support

### Stable
- Extensively tested
- Production-ready
- Full documentation
- Active maintainer
- CI/CD integration

**Progression**: Experimental → Beta → Stable (typically 3-6 months)

---

## Examples

### Successful Platform Contributions

1. **Orange Pi 5 Plus** (`platforms/orangepi/`)
   - U-Boot bootloader
   - ARM64 architecture
   - Armbian-based

2. **Raspberry Pi 4B** (`platforms/raspberrypi/`)
   - Pi firmware bootloader
   - ARM64 architecture
   - Raspbian-based

### Reference Profiles

- Simple profile: `platforms/raspberrypi/profiles/3b-plus.yaml`
- Complex profile: `platforms/orangepi/profiles/5-plus.yaml`
- Minimal profile: `platforms/raspberrypi/profiles/zero-w.yaml`

---

## Frequently Asked Questions

### Q: Can I add support for x86/x64 hardware?

A: Currently, the build system focuses on ARM platforms. x86 support would require significant changes to the build pipeline.

### Q: What if my platform uses a custom kernel?

A: Create a hook to build and install the custom kernel. See existing hooks for examples.

### Q: How do I test without real hardware?

A: Use QEMU for initial testing, but real hardware testing is required before beta status.

### Q: Can I maintain multiple platforms?

A: Yes! You can be maintainer for multiple platforms if you have the time and hardware.

### Q: What if I can't commit to long-term maintenance?

A: You can still contribute! Mark it as "experimental" and note in the PR that you're contributing without ongoing maintenance commitment. The community may adopt it later.

---

## Getting Help

- **Documentation**: [Hardware Profiles Reference](../architecture/hardware-profiles.md)
- **Issues**: [GitHub Issues](https://github.com/yourorg/pi-router-build/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourorg/pi-router-build/discussions)
- **Chat**: Slack #platform-development

---

## Related Documentation

- [Multi-Platform Strategy](../architecture/multi-platform-strategy.md)
- [Hardware Profiles Schema](../architecture/hardware-profiles.md)
- [Migration Roadmap](../architecture/migration-roadmap.md)

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2025-01-06 | Core Team | Initial contribution guide |

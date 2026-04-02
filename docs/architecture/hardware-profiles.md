# Hardware Profiles System

## Overview

Hardware profiles are YAML files that describe platform-specific configurations for building
router images. Each profile contains all the information needed to build a bootable image for
a specific ARM single-board computer.

**Location**: `platforms/${PLATFORM}/profiles/${MODEL}.yaml`

**Purpose**: Replace hardcoded hardware-specific values throughout build scripts with declarative configuration.

## Profile Schema Reference

### Complete Example

```yaml
# platforms/raspberrypi/profiles/3b-plus.yaml

# Metadata
metadata:
  platform: raspberrypi
  model: 3B+
  display_name: "Raspberry Pi 3 Model B+"
  vendor: Raspberry Pi Foundation
  maintainer: core
  status: stable  # stable, beta, experimental
  documentation_url: https://www.raspberrypi.com/products/raspberry-pi-3-model-b-plus/

# Hardware specifications
hardware:
  architecture: armhf          # armhf, arm64, riscv64
  soc: BCM2710                 # System-on-Chip identifier
  cpu_cores: 4
  cpu_freq_mhz: 1400
  ram_mb: 1024
  storage_interface: sdcard    # sdcard, emmc, nvme, sata
  network:
    ethernet: true
    ethernet_speed_mbps: 1000
    wifi: true
    wifi_chip: bcm43455
    bluetooth: true

# Bootloader configuration
bootloader:
  type: pi-firmware            # pi-firmware, u-boot, grub, coreboot
  partition_type: vfat         # vfat, ext4
  partition_size: 256M         # Boot partition size
  partition_label: boot

  # Pi firmware specific files
  files:
    - bootcode.bin
    - start.elf
    - start_x.elf
    - start_cd.elf
    - fixup.dat
    - fixup_x.dat
    - fixup_cd.dat

  # Boot configuration template (Jinja2)
  config_template: platforms/raspberrypi/templates/config.txt.j2

  # Device tree blob
  device_tree: bcm2710-rpi-3-b-plus.dtb

  # Additional device tree overlays
  device_tree_overlays:
    - pi3-disable-bt.dtbo
    - pi3-miniuart-bt.dtbo

# Operating system configuration
os:
  distribution: raspbian       # raspbian, debian, ubuntu, armbian
  version: bullseye            # Codename: bullseye, bookworm, trixie
  mirror: http://archive.raspbian.org/raspbian/
  architecture: armhf          # Must match hardware.architecture

  # Additional APT repositories
  additional_repos:
    - name: raspberrypi
      url: http://archive.raspberrypi.org/debian/
      key_url: https://archive.raspberrypi.org/debian/raspberrypi.gpg.key
      components: main ui

# Package configuration
packages:
  # Kernel package
  kernel: raspberrypi-kernel

  # Firmware packages
  firmware:
    - libraspberrypi-bin
    - libraspberrypi0
    - firmware-brcm80211       # WiFi firmware
    - pi-bluetooth             # Bluetooth firmware

  # Hardware-specific utilities
  utilities:
    - raspi-config
    - rpi-update

  # Additional packages
  additional:
    - wireless-tools

# Storage configuration
storage:
  device: mmcblk0              # Device name (without /dev/)
  root_partition_suffix: p2    # Root partition: /dev/mmcblk0p2
  boot_partition_suffix: p1    # Boot partition: /dev/mmcblk0p1

  # Filesystem types
  boot_fs: vfat
  root_fs: ext4

  # Partition layout (optional, defaults used if not specified)
  partitions:
    - type: boot
      size: 256M
      filesystem: vfat
      mount: /boot
    - type: root
      size: remaining
      filesystem: ext4
      mount: /

# Performance tuning
performance:
  # config.txt parameters (Pi-specific)
  arm_freq: 1200
  core_freq: 400
  sdram_freq: 450
  over_voltage: 2
  gpu_mem: 16

  # Force turbo mode (use with caution)
  force_turbo: false

  # Temperature limits
  temp_limit: 85

# Hardware features
features:
  uart: true
  spi: true
  i2c: true
  gpio: true
  camera: true
  audio: true

  # Hardware-specific groups to create
  hardware_groups:
    - gpio
    - i2c
    - spi
    - video
    - audio
    - input

# Network configuration defaults
network:
  # Default interface names
  wan_interface: eth0
  lan_interface: wlan0

  # Management interface (if different from WAN/LAN)
  mgmt_interface: eth0:0
  mgmt_ip: 172.16.0.1
  mgmt_netmask: 255.255.255.0

# Security configuration
security:
  # SSH configuration
  ssh_port: 22
  ssh_permit_root: false
  ssh_password_auth: false

  # Default firewall rules
  firewall_default_policy: DROP

  # SELinux/AppArmor
  selinux: false
  apparmor: false

# Testing configuration
testing:
  # QEMU machine type for emulation testing
  qemu_machine: raspi3b

  # Expected boot time (seconds)
  expected_boot_time: 60

  # Minimum required tests
  required_tests:
    - boot
    - network
    - ssh

  # Platform-specific tests
  platform_tests:
    - gpio_access
    - i2c_detection

# Build configuration
build:
  # Cache key version (increment to invalidate cache)
  cache_version: 1

  # Expected build time (minutes) for benchmarking
  expected_build_time: 10

  # Parallel jobs (for make -j)
  parallel_jobs: 4

  # Compression format for final image
  compression: xz  # xz, gzip, bzip2, none
```

## Schema Sections

### 1. Metadata Section

Describes the profile itself and its maintenance status.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `platform` | string | Yes | Platform identifier (lowercase, no spaces) |
| `model` | string | Yes | Model identifier (matches filename) |
| `display_name` | string | No | Human-readable name |
| `vendor` | string | No | Hardware manufacturer |
| `maintainer` | string | Yes | `core` or GitHub username |
| `status` | enum | Yes | `stable`, `beta`, `experimental` |
| `documentation_url` | string | No | Link to vendor documentation |

**Example**:

```yaml
metadata:
  platform: orangepi
  model: 5-plus
  display_name: "Orange Pi 5 Plus"
  vendor: Shenzhen Xunlong Software
  maintainer: community/orangepi-maintainer
  status: beta
```

### 2. Hardware Section

Physical hardware specifications.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `architecture` | enum | Yes | `armhf`, `arm64`, `riscv64` |
| `soc` | string | Yes | System-on-Chip identifier |
| `cpu_cores` | integer | No | Number of CPU cores |
| `cpu_freq_mhz` | integer | No | CPU frequency in MHz |
| `ram_mb` | integer | No | RAM size in megabytes |
| `storage_interface` | enum | Yes | `sdcard`, `emmc`, `nvme`, `sata` |

**Example (Orange Pi 5+)**:

```yaml
hardware:
  architecture: arm64
  soc: RK3588
  cpu_cores: 8
  cpu_freq_mhz: 2400
  ram_mb: 16384
  storage_interface: emmc
```

### 3. Bootloader Section

Bootloader and boot partition configuration.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | enum | Yes | `pi-firmware`, `u-boot`, `grub`, `coreboot` |
| `partition_type` | string | Yes | Filesystem type for boot partition |
| `partition_size` | string | Yes | Boot partition size (e.g., `256M`) |
| `files` | array | No | Required bootloader files |
| `config_template` | string | No | Path to boot config template |
| `device_tree` | string | No | Device tree blob filename |

**Example (U-Boot for Orange Pi)**:

```yaml
bootloader:
  type: u-boot
  partition_type: ext4
  partition_size: 512M
  files:
    - u-boot.bin
    - trust.img
  config_template: platforms/orangepi/templates/boot.scr.j2
  device_tree: rk3588-orangepi-5-plus.dtb
```

### 4. OS Section

Operating system and package repository configuration.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `distribution` | enum | Yes | `raspbian`, `debian`, `ubuntu`, `armbian` |
| `version` | string | Yes | Release codename |
| `mirror` | string | Yes | APT repository mirror URL |
| `architecture` | string | Yes | Debian architecture name |
| `additional_repos` | array | No | Extra APT repositories |

**Example (Armbian)**:

```yaml
os:
  distribution: armbian
  version: bookworm
  mirror: http://apt.armbian.com/
  architecture: arm64
  additional_repos:
    - name: armbian-orangepi
      url: http://apt.armbian.com/
      key_url: http://apt.armbian.com/armbian.key
      components: main bookworm-utils bookworm-desktop
```

### 5. Packages Section

Package selection for the platform.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `kernel` | string | Yes | Kernel package name |
| `firmware` | array | No | Firmware packages |
| `utilities` | array | No | Platform-specific utilities |
| `additional` | array | No | Other required packages |

**Example**:

```yaml
packages:
  kernel: linux-image-current-rockchip-rk3588
  firmware:
    - firmware-realtek
    - armbian-firmware
  utilities:
    - orangepi-config
  additional:
    - network-manager
```

### 6. Storage Section

Storage device and partition configuration.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `device` | string | Yes | Device name without `/dev/` |
| `root_partition_suffix` | string | Yes | Root partition suffix |
| `boot_partition_suffix` | string | Yes | Boot partition suffix |
| `boot_fs` | string | Yes | Boot filesystem type |
| `root_fs` | string | Yes | Root filesystem type |

**Device Naming Examples**:

- SD card: `mmcblk0` → partitions: `mmcblk0p1`, `mmcblk0p2`
- eMMC: `mmcblk1` → partitions: `mmcblk1p1`, `mmcblk1p2`
- NVMe: `nvme0n1` → partitions: `nvme0n1p1`, `nvme0n1p2`
- SATA: `sda` → partitions: `sda1`, `sda2`

### 7. Features Section

Hardware capabilities and required system groups.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `uart` | boolean | No | Serial console support |
| `spi` | boolean | No | SPI bus support |
| `i2c` | boolean | No | I2C bus support |
| `gpio` | boolean | No | GPIO pins support |
| `hardware_groups` | array | No | System groups to create |

**Example**:

```yaml
features:
  uart: true
  spi: true
  i2c: true
  gpio: true
  hardware_groups:
    - gpio
    - i2c
    - spi
```

### 8. Testing Section

Testing and validation configuration.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `qemu_machine` | string | No | QEMU machine type for testing |
| `expected_boot_time` | integer | No | Expected boot time in seconds |
| `required_tests` | array | No | Minimum required tests |
| `platform_tests` | array | No | Platform-specific tests |

**Example**:

```yaml
testing:
  qemu_machine: raspi3b
  expected_boot_time: 60
  required_tests:
    - boot
    - network
    - ssh
  platform_tests:
    - gpio_access
```

## Profile Loading Process

### 1. Profile Discovery

```bash
# Build script determines profile path
PLATFORM="${PIMELEON_PLATFORM:-raspberrypi}"
MODEL="${PIMELEON_MODEL:-3B+}"
PROFILE_PATH="platforms/${PLATFORM}/profiles/${MODEL}.yaml"
```

### 2. Profile Validation

```bash
# Validate YAML syntax and required fields
validate_profile() {
    local profile="$1"

    # Check file exists
    [[ -f "${profile}" ]] || die "Profile not found: ${profile}"

    # Validate YAML syntax
    yq eval '.' "${profile}" > /dev/null || die "Invalid YAML syntax"

    # Check required fields
    local required_fields=(
        "metadata.platform"
        "metadata.model"
        "hardware.architecture"
        "bootloader.type"
        "os.distribution"
        "packages.kernel"
        "storage.device"
    )

    for field in "${required_fields[@]}"; do
        yq eval ".${field}" "${profile}" > /dev/null || \
            die "Missing required field: ${field}"
    done
}
```

### 3. Profile Parsing

```bash
# Load profile into environment variables
load_hardware_profile() {
    local profile="$1"

    validate_profile "${profile}"

    # Export variables with HW_ prefix
    export HW_PLATFORM=$(yq eval '.metadata.platform' "${profile}")
    export HW_MODEL=$(yq eval '.metadata.model' "${profile}")
    export HW_ARCHITECTURE=$(yq eval '.hardware.architecture' "${profile}")
    export HW_SOC=$(yq eval '.hardware.soc' "${profile}")

    export BOOT_TYPE=$(yq eval '.bootloader.type' "${profile}")
    export BOOT_PARTITION_SIZE=$(yq eval '.bootloader.partition_size' "${profile}")
    export BOOT_DEVICE_TREE=$(yq eval '.bootloader.device_tree' "${profile}")

    export OS_DISTRIBUTION=$(yq eval '.os.distribution' "${profile}")
    export OS_VERSION=$(yq eval '.os.version' "${profile}")
    export OS_MIRROR=$(yq eval '.os.mirror' "${profile}")

    export STORAGE_DEVICE=$(yq eval '.storage.device' "${profile}")
    export STORAGE_ROOT_SUFFIX=$(yq eval '.storage.root_partition_suffix' "${profile}")

    # Arrays require special handling
    PACKAGES_KERNEL=$(yq eval '.packages.kernel' "${profile}")
    PACKAGES_FIRMWARE=($(yq eval '.packages.firmware[]' "${profile}"))
}
```

### 4. Profile Usage in Build Stages

```bash
# stage2-customize.sh

# Install kernel from profile
chroot_run apt-get install -y "${PACKAGES_KERNEL}"

# Install firmware packages
for pkg in "${PACKAGES_FIRMWARE[@]}"; do
    chroot_run apt-get install -y "${pkg}"
done

# Copy device tree if specified
if [[ -n "${BOOT_DEVICE_TREE}" ]]; then
    sudo cp "${MOUNT_POINT}/boot/${BOOT_DEVICE_TREE}" "${BOOT_MOUNT}/"
fi

# Generate boot configuration from template
if [[ -n "${BOOT_CONFIG_TEMPLATE}" ]]; then
    render_template "${BOOT_CONFIG_TEMPLATE}" > "${BOOT_MOUNT}/config.txt"
fi
```

## Creating New Profiles

### Step 1: Copy Template

```bash
# Use Pi 3B+ as template
cp platforms/raspberrypi/profiles/3b-plus.yaml \
   platforms/orangepi/profiles/5-plus.yaml
```

### Step 2: Update Metadata

```yaml
metadata:
  platform: orangepi        # Change platform
  model: 5-plus             # Change model
  display_name: "Orange Pi 5 Plus"
  vendor: Shenzhen Xunlong Software
  maintainer: yourname      # Your GitHub username
  status: experimental      # Start as experimental
```

### Step 3: Update Hardware Specs

```yaml
hardware:
  architecture: arm64       # Orange Pi 5+ is 64-bit
  soc: RK3588              # Rockchip RK3588
  cpu_cores: 8
  ram_mb: 16384            # 16GB variant
  storage_interface: emmc
```

### Step 4: Configure Bootloader

```yaml
bootloader:
  type: u-boot              # Orange Pi uses U-Boot
  partition_type: ext4
  partition_size: 512M
  device_tree: rk3588-orangepi-5-plus.dtb
  config_template: platforms/orangepi/templates/boot.scr.j2
```

### Step 5: Configure OS

```yaml
os:
  distribution: armbian     # Orange Pi typically uses Armbian
  version: bookworm
  mirror: http://apt.armbian.com/
  architecture: arm64
```

### Step 6: Update Packages

```yaml
packages:
  kernel: linux-image-current-rockchip-rk3588
  firmware:
    - firmware-realtek
    - armbian-firmware
```

### Step 7: Configure Storage

```yaml
storage:
  device: mmcblk1           # eMMC is typically mmcblk1
  root_partition_suffix: p2
  boot_partition_suffix: p1
```

### Step 8: Test Profile

```bash
# Validate YAML syntax
yq eval '.' platforms/orangepi/profiles/5-plus.yaml

# Test build
PIMELEON_PLATFORM=orangepi PIMELEON_MODEL=5-plus make build
```

## Boot Configuration Templates

### Pi Firmware Template (config.txt)

```jinja2
{# platforms/raspberrypi/templates/config.txt.j2 #}

# Raspberry Pi {{ HW_MODEL }} Configuration

# Boot parameters
enable_uart={{ 1 if FEATURES_UART else 0 }}
dtparam=spi={{ 'on' if FEATURES_SPI else 'off' }}
dtparam=i2c_arm={{ 'on' if FEATURES_I2C else 'off' }}

# Performance
arm_freq={{ PERF_ARM_FREQ }}
gpu_mem={{ PERF_GPU_MEM }}
over_voltage={{ PERF_OVER_VOLTAGE }}

# Device tree
dtoverlay=vc4-kms-v3d
```

### U-Boot Template (boot.scr)

```bash
# platforms/orangepi/templates/boot.scr.j2

# Orange Pi {{ HW_MODEL }} U-Boot Script

setenv bootargs "console=ttyS2,1500000 root=/dev/{{ STORAGE_DEVICE }}{{ STORAGE_ROOT_SUFFIX }} rootfstype={{ STORAGE_ROOT_FS }} rootwait"

load mmc 0:1 ${kernel_addr_r} /Image
load mmc 0:1 ${fdt_addr_r} /dtb/rockchip/{{ BOOT_DEVICE_TREE }}

booti ${kernel_addr_r} - ${fdt_addr_r}
```

## Validation Tools

### Profile Validator Script

```bash
#!/bin/bash
# scripts/validate-profile.sh

PROFILE="$1"

echo "Validating profile: ${PROFILE}"

# Check YAML syntax
yq eval '.' "${PROFILE}" > /dev/null || exit 1

# Check required fields
required_fields=(
    "metadata.platform"
    "metadata.model"
    "metadata.maintainer"
    "metadata.status"
    "hardware.architecture"
    "bootloader.type"
    "os.distribution"
    "packages.kernel"
    "storage.device"
)

for field in "${required_fields[@]}"; do
    value=$(yq eval ".${field}" "${PROFILE}")
    if [[ "${value}" == "null" ]]; then
        echo "ERROR: Missing required field: ${field}"
        exit 1
    fi
done

echo "✅ Profile validation passed"
```

### Usage

```bash
# Validate single profile
./scripts/validate-profile.sh platforms/raspberrypi/profiles/3b-plus.yaml

# Validate all profiles
find platforms -name "*.yaml" -exec ./scripts/validate-profile.sh {} \;
```

## Related Documentation

- [Multi-Platform Strategy](multi-platform-strategy.md) - Overall architecture
- [Migration Roadmap](migration-roadmap.md) - Implementation timeline
- [Contributing Platforms](../contributing/adding-platforms.md) - Contribution guide

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2025-01-06 | Core Team | Initial schema documentation |

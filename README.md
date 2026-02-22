# Pimeleon Build System

A containerized monorepo build system for creating Raspberry Pi router images with ARM emulation and automated testing.

📚 **[Documentation](https://docs.pimeleon.org)** |
🚀 [Quick Start](https://docs.pimeleon.org/getting-started/) |
🏗️ [Architecture](https://docs.pimeleon.org/architecture/overview/)

## 🚀 Quick Start

### Prerequisites

- Docker with BuildKit enabled
- 50GB+ free disk space
- Host system with `binfmt-support` and `qemu-user-static`:

  ```bash
  sudo apt install binfmt-support qemu-user-static
  ```

### Build Your First Image

```bash
# Clone the repository
git clone <repository-url>
cd pimeleon-build

# List available apps (device targets)
make list-apps

# Build for Raspberry Pi 3B+ (default)
make build APP=rpi3-bookworm

# Build for Raspberry Pi 4B
make build APP=rpi4-bookworm
```

The resulting image will be in `output/pimeleon-{app}-YYYYMMDD-HHMMSS.img`

### Available Apps

| App | Device | Debian | Architecture |
|-----|--------|--------|--------------|
| `rpi3-bookworm` | Raspberry Pi 3B+ | Bookworm | armhf |
| `rpi4-bookworm` | Raspberry Pi 4B | Bookworm | arm64 |

**Required packages** (for local builds): debootstrap, qemu-user-static, binfmt-support,
kpartx, parted, ansible, dosfstools, e2fsprogs, rsync, xz-utils

## 🏗️ System Architecture

### Build Process

The system uses a **2-stage** build process (currently implemented):

1. **Stage 1: Base System** - Bootstrap Raspbian Buster using debootstrap
2. **Stage 2: Customization** - Install packages, configure networking, create users

### Containers

- **builder**: Debian 12 container with ARM cross-compilation tools
- **tester**: Ubuntu 22.04 with QEMU/KVM for testing (optional)
- **dev**: Development environment (shares builder Dockerfile)

### Key Features

- ✅ **ARM Emulation**: Build ARM images on x86 hardware with QEMU user-mode
- ✅ **Pi Boot Firmware**: Includes complete Raspberry Pi firmware (bootcode.bin, start.elf, kernels)
- ✅ **Smart Build Caching**: Hardware-specific caches (`pimeleon-rpi3-bullseye-base-v1.tar.gz`)
- ✅ **APT Cache Integration**: TrueNAS apt-cacher-ng support (192.168.76.5:3142) with 95% hit rate
- ✅ **Pi Foundation Repository**: Official Pi packages (raspberrypi-kernel, libraspberrypi-bin)
- ✅ **systemd-networkd**: Production-matched networking configuration
- ✅ **Security Hardening**: SSH key-only auth, Pi-specific groups, restricted sudo access
- ✅ **Build Benchmarking**: Automated performance metrics and system analysis

## 📋 Available Commands

### Makefile Targets

```bash
# Build operations
make build APP=<app>    # Build specified app (default: rpi3-bookworm)
make build-all          # Build all apps
make build-prod APP=<app>  # Production build
make build-nocache APP=<app>  # Build without Docker cache
make list-apps          # List available apps
make check-deps         # Check local build dependencies

# Testing
make test APP=<app>     # Run all tests for app
make test-smoke APP=<app>  # Run smoke tests only

# Development
make dev                # Start development environment
make shell APP=<app>    # Open shell in builder container
make lint               # Run all linters
make clean              # Clean build artifacts
make clean-cache        # Clean build cache
make clean-all          # Full cleanup (containers, images, cache)

# Utilities
make logs               # Follow container logs
make ps                 # Show running containers
make version            # Show version info
make ci-local APP=<app> # Run local CI pipeline
```

### Docker Commands

> **IMPORTANT:** Always use Makefile targets instead of running `docker compose build` directly.
> The build requires the `pimeleon-adblock2privoxy` image which is automatically built by the Makefile.
> Running `docker compose build` directly will fail if this image is missing.

```bash
# RECOMMENDED: Use Makefile targets (auto-handles dependencies)
make build APP=rpi3-bookworm
make build-nocache APP=rpi3-bookworm

# Build adblock2privoxy image (done automatically by make build)
make build-ab2p

# Interactive shell for debugging
TARGET_PLATFORM=rpi3-bookworm docker compose run --rm builder bash

# View logs
docker compose logs -f builder

# Stop and remove containers
docker compose down

# Full cleanup (containers, volumes, images)
# NOTE: This removes adblock2privoxy image - will be rebuilt on next make build
docker compose down -v --rmi all
```

### Fixing Common Issues

```bash
# Fix output directory permissions
sudo chown -R $USER:$USER output/

# Rebuild Docker image after Dockerfile changes
make build-nocache APP=rpi3-bookworm

# Clean up stuck containers
docker compose down --remove-orphans

# Remove all build artifacts and start fresh
make clean-all
make build APP=rpi3-bookworm
```

## 📁 Project Structure

```shell
pimeleon-build/
├── apps/                           # Device-specific configurations
│   ├── rpi3-bookworm/              # Raspberry Pi 3B+ Bookworm
│   │   └── vars/                   # Device-specific Ansible vars
│   └── rpi4-bookworm/              # Raspberry Pi 4B Bookworm
│       └── vars/                   # Device-specific Ansible vars
├── shared/                         # Shared build components
│   ├── ansible/                    # Ansible configuration
│   │   ├── playbooks/              # Playbooks and tasks
│   │   ├── vars/                   # Shared variables
│   │   │   ├── common/             # Global defaults
│   │   │   └── platform/           # Platform-specific (raspberrypi/)
│   │   └── ansible.cfg             # Ansible configuration
│   ├── scripts/                    # Build scripts
│   │   ├── build.sh                # Main orchestrator
│   │   ├── common.sh               # Shared functions
│   │   ├── stage1-base.sh          # Raspbian bootstrap
│   │   ├── stage2-customize.sh     # System configuration
│   │   ├── stage3-optimize.sh      # (TODO: Cleanup)
│   │   └── stage4-package.sh       # (TODO: Compression)
│   └── containers/                 # Docker containers
│       ├── builder/                # Build container
│       └── tester/                 # Test container
├── cache/                          # Persistent build cache
├── output/                         # Generated images and logs
├── configs/                        # Pi configuration files
├── Makefile                        # Build targets
└── docker-compose.yml              # Service orchestration
```

## 🔧 Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_PLATFORM=` | `rpi3-bookworm` | App to build (determines device, arch, debian) |
| `PIMELEON_PROFILE` | `development` | Build profile (`development`, `production`) |
| `PIMELEON_IMAGE_SIZE` | `4G` | Output image size |
| `APT_CACHE_SERVER` | - | APT cache server IP (e.g., `192.168.76.5`) |
| `APT_CACHE_PORT` | `3142` | APT cache server port |

**Derived from app name** (e.g., `rpi3-bookworm`):

- `PIMELEON_RPI_MODEL` - Pi model (`3B+`, `4B`)
- `RPI_ARCH` - Architecture (`armhf`, `arm64`)
- `RASPBIAN_VERSION` - Debian version (`bookworm`)

### Build Profiles

| Profile | Description |
|---------|-------------|
| `development` | Full services + debug tools (htop, tcpdump, strace, gdb, etc.), permissive SSH |
| `production` | Full services, hardened SSH (port 24442, key-only), no debug tools |

### Build Examples

```bash
# Pi 3B+ development build (default)
make build APP=rpi3-bookworm

# Pi 4B development build
make build APP=rpi4-bookworm

# Production build (hardened)
make build-prod APP=rpi3-bookworm

# Build all apps
make build-all

# With APT cache for faster builds
APT_CACHE_SERVER=192.168.76.5 make build APP=rpi3-bookworm

# Custom image size
PIMELEON_IMAGE_SIZE=8G make build APP=rpi3-bookworm

# Interactive debugging
make shell APP=rpi3-bookworm
```

### Build Outputs

- **Images**: `output/pimeleon-{app}-YYYYMMDD-HHMMSS.img` (4GB bootable image with Pi firmware)
- **Logs**: `output/build-{app}-YYYYMMDD-HHMMSS.log` (detailed build logs)
- **Credentials**: `output/pi-initial-password.txt` (generated password for pi user)
- **Metadata**: `output/pimeleon-{app}-YYYYMMDD-HHMMSS.img.metadata.json` (checksums, build info)
- **Cache**: `cache/` (reusable base system)

## 🚨 Common Issues & Solutions

### Build Issues

❌ "chroot: failed to run command"

```bash
# Install ARM binary format support on host
sudo apt install binfmt-support qemu-user-static
```

❌ "Permission denied" during configuration

- Fixed: Scripts now use `sudo tee` for proper permissions

❌ "useradd: group 'gpio' does not exist"

- **Solution**: Pi-specific groups (gpio, i2c, spi) are automatically created before user creation

❌ Build hangs at package installation

```bash
# Check APT cache connectivity
ping 192.168.76.5

# Use direct downloads if cache unavailable
unset APT_CACHE_SERVER
docker compose run --rm builder
```

❌ "No space left on device"

```bash
# Clean Docker cache while preserving base images
./scripts/clean-docker.sh

# Check available space (need 50GB+)
df -h
```

### Performance Issues

**Slow builds:**

- **APT Cache**: Builds use TrueNAS apt-cacher-ng automatically (95% hit rate)
- **Smart Caching**: Base system cached as `pimeleon-rpi3-bullseye-base-v1.tar.gz`
- **Hardware-specific**: Separate caches for different Pi models and OS versions
- Use SSD storage for better I/O performance
- Run `./scripts/benchmark-build.sh` to analyze build performance

**Out of memory:**

```bash
# Increase Docker memory limit
# In Docker Desktop: Settings > Resources > Memory > 8GB+
```

### Display Issues

**❓ Duplicate network creation messages during tester startup:**

```
[+] Creating 5/5uter-build_lan-network   Created
✔ Network pimeleon-build_wan-network   Created
✔ Network pimeleon-build_wan-network   Created  # <- Duplicate line
```

This is a **harmless Docker Compose display glitch** that occurs during parallel network creation.
The networks are created correctly (verify with `docker network ls`). To suppress:

```bash
# Use quiet progress mode
docker compose --progress quiet run tester

# Or disable parallel creation
docker compose --parallel 1 run tester
```

**❓ Authorization warnings in tester container:**

```
Authorization not available. Check if polkit service is running or see debug message for more information.
error: failed to mark network default as autostarted
```

These are **expected and harmless warnings** in containerized libvirt environments.
The libvirt operations still succeed despite the authorization messages because:

- Containers don't have full systemd/polkit integration
- libvirt functionality works correctly regardless
- Networks are created and started successfully

**❓ Permission denied during cleanup:**

```
truncate: cannot open '/tmp/build/mount/var/log/dpkg.log' for writing: Permission denied
rm: cannot remove '/tmp/build/mount/var/lib/apt/lists/lock': Permission denied
```

These are **expected and harmless warnings** during image cleanup. The build completes successfully
despite these messages, which occur because some files are owned by root in the chroot environment.

You can safely ignore these messages or suppress them by using the updated entrypoint script.

## 🛠️ Development

### Adding Custom Configurations

1. Place files in `configs/network/`, `configs/security/`, etc.
2. Update `shared/scripts/stage2-customize.sh` or Ansible playbooks
3. Rebuild: `make build APP=rpi3-bookworm`

### Adding a New Device

1. Create app directory: `mkdir -p apps/{device}-{debian}/vars`
2. Copy vars from similar device: `cp apps/rpi3-bookworm/vars/* apps/new-device/vars/`
3. Update vars for new device in `apps/new-device/vars/main.yml`
4. Add device case to `shared/scripts/common.sh` in `load_app_config()`
5. Test: `make build APP=new-device`

### Debugging Builds

```bash
# View detailed logs
tail -f output/build-rpi3-bookworm-*.log

# Interactive debugging
make shell APP=rpi3-bookworm
# Then manually run: /scripts/build.sh
```

### Testing Images

```bash
# Basic functionality test
docker compose run --rm tester

# Manual testing with QEMU
qemu-system-arm -M raspi3 -kernel output/pimeleon-*.img
```

## 🔒 Security Notes

### Build Security

- Builder runs as non-root user with restricted sudo access
- Host system isolation via containerization
- No secrets in build logs

### Generated Images

- SSH root login disabled
- Pi user with key-based authentication only
- Firewall configured with iptables
- systemd-networkd for network management

## 🎯 Current Status

### ✅ Working Features

- **Complete Pi Boot Support**: Raspberry Pi firmware (bootcode.bin, start.elf, kernel images)
- **Debian 12 Build Container**: ARM cross-compilation with QEMU user-mode emulation
- **Raspbian Buster Base**: Official Pi Foundation repository integration
- **Smart Build Caching**: Hardware-specific caches with version tracking
- **APT Cache Integration**: TrueNAS apt-cacher-ng with 95% hit rate
- **Package Installation**: Essential packages, Pi kernel, and networking tools
- **Network Configuration**: Production-matched systemd-networkd setup
- **User Management**: Pi user with Pi-specific groups (gpio, i2c, spi)
- **SSH Hardening**: Key-based authentication, no root access
- **Build Benchmarking**: Automated performance analysis and metrics
- **Image Generation**: 4GB bootable images ready for SD card flashing

### 🚧 In Development

- Stage 3: Image optimization and cleanup
- Stage 4: Compression and metadata generation
- Comprehensive test framework
- CI/CD pipeline integration

### 📈 Performance

#### Build Performance Benchmarks (Fresh Base System)

- **With TrueNAS APT Cache**: 10:12 (612 seconds) - Recommended
- **Without APT Cache**: 19:49 (1189 seconds) - Direct downloads
- **Performance Improvement**: 48.5% faster with APT cache (10 minutes saved)

#### Subsequent Builds (Cached Base System)

- **With APT Cache**: ~5-8 minutes (base system reuse + cached packages)
- **Cache Hit Rate**: 95%+ on TrueNAS APT cache (192.168.76.5:3142)
- **Base System Caching**: 85% time reduction when `pimeleon-rpi3-bullseye-base-v1.tar.gz` exists

#### Build Analysis Tools

- **Benchmarking**: `./scripts/benchmark-build.sh` - Comprehensive performance analysis
- **No-Cache Comparison**: `./scripts/benchmark-build.sh --no-cache` - Baseline measurement
- **Output**: Detailed metrics in `benchmarks/build-benchmark-*.json`
- **Image Size**: 4GB raw image, ~1.5GB when compressed (stage 4)

## 📞 Support

- Build issues: Check `output/build-*.log` files
- Permission errors: Ensure proper sudo configuration
- Network problems: Verify APT cache connectivity
- Performance: Use SSD storage and enable caching

The system is actively developed and tested with Raspberry Pi 3B+ hardware running Raspbian Buster.

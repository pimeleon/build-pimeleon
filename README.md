# Pi Router Build System

A containerized build system for creating Raspberry Pi 3B+ router images with ARM emulation and automated testing.

📚 **[Complete Documentation](https://docs.pimeleon.com)** | 🚀 [Quick Start](https://docs.pimeleon.com/getting-started/) | 🏗️ [Architecture](https://docs.pimeleon.com/architecture/overview/)

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
cd pi-router-build

# Build containers (with APT cache optimization)
docker compose build

# Create Pi Router image
docker compose run --rm builder
```

The resulting image will be in `output/pi-router-YYYYMMDD-HHMMSS.img`

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
- ✅ **Smart Build Caching**: Hardware-specific caches (`pirouter-rpi3-buster-base-v1.tar.gz`)
- ✅ **APT Cache Integration**: TrueNAS apt-cacher-ng support (192.168.76.5:3142) with 95% hit rate
- ✅ **Pi Foundation Repository**: Official Pi packages (raspberrypi-kernel, libraspberrypi-bin)
- ✅ **systemd-networkd**: Production-matched networking configuration
- ✅ **Security Hardening**: SSH key-only auth, Pi-specific groups, restricted sudo access
- ✅ **Build Benchmarking**: Automated performance metrics and system analysis

## 📋 Available Commands

### Basic Operations
```bash
# Build all containers
docker compose build

# Build specific container
docker compose build builder

# Run image build
docker compose run --rm builder

# Run with custom environment
IMAGE_SIZE=8G docker compose run --rm builder

# Development shell
docker compose run --rm builder bash
```

### Build Optimization

```bash
# Use APT cache (automatic if TrueNAS detected)
APT_CACHE_SERVER=192.168.76.5 docker compose run --rm builder

# Run with comprehensive benchmarking (auto-detects APT cache)
./scripts/benchmark-build.sh

# Compare performance with and without APT cache optimization  
./scripts/benchmark-build.sh --no-cache

# Testing mode (stages 1-2 only, faster builds)
# Stages 3-4 temporarily disabled for rapid iteration
docker compose run --rm builder

# Clean Docker caches while preserving base images  
./scripts/clean-docker.sh

# Clean output directory keeping latest image
./scripts/clean-docker.sh --clean-output

# Full cleanup (removes everything)
./scripts/clean-docker.sh --full
```

## 📁 Project Structure

```shell
pi-router-build/
├── containers/
│   ├── builder/                    # Build container
│   │   ├── Dockerfile              # Multi-stage build definition
│   │   └── scripts/                # Build scripts
│   │       ├── build.sh            # Main orchestrator
│   │       ├── common.sh           # Shared functions
│   │       ├── stage1-base.sh      # Raspbian bootstrap
│   │       ├── stage2-customize.sh # System configuration
│   │       ├── stage3-optimize.sh  # (TODO: Cleanup)
│   │       └── stage4-package.sh   # (TODO: Compression)
│   └── tester/                     # Test container (optional)
├── cache/                          # Persistent build cache
├── output/                         # Generated images and logs
├── configs/                        # Pi configuration files
├── ansible/                        # Configuration management
├── scripts/                        # Utility scripts
│   ├── clean-docker.sh             # Selective cache cleanup
│   └── benchmark-build.sh          # Build performance analysis
├── benchmarks/                     # Build performance data
└── docker-compose.yml              # Service orchestration
```

## 🔧 Configuration

### Environment Variables

- `RPI_MODEL=3B+` - Target Raspberry Pi model
- `IMAGE_SIZE=4G` - Output image size  
- `RASPBIAN_VERSION=buster` - Base OS version
- `APT_CACHE_SERVER=192.168.76.5` - APT cache server (auto-configured)
- `QUIET=true` - Suppress verbose output

### Build Outputs

- **Images**: `output/pi-router-YYYYMMDD-HHMMSS.img` (4GB bootable image with Pi firmware)
- **Logs**: `output/build-YYYYMMDD-HHMMSS.log` (detailed build logs)
- **Credentials**: `output/pi-initial-password.txt` (generated password for pi user)
- **Benchmarks**: `benchmarks/build-benchmark-YYYYMMDD-HHMMSS.json` (performance metrics)
- **Cache**: `cache/pirouter-rpi3-buster-base-v1.tar.gz` (reusable base system)

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
- **Smart Caching**: Base system cached as `pirouter-rpi3-buster-base-v1.tar.gz` 
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
✔ Network pi-router-build_wan-network   Created
✔ Network pi-router-build_wan-network   Created  # <- Duplicate line
```

This is a **harmless Docker Compose display glitch** that occurs during parallel network creation. The networks are created correctly (verify with `docker network ls`). To suppress the confusing output:

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

These are **expected and harmless warnings** in containerized libvirt environments. The libvirt operations still succeed despite the authorization messages. The warnings occur because:

- Containers don't have full systemd/polkit integration
- libvirt functionality works correctly regardless
- Networks are created and started successfully

**❓ Permission denied during cleanup:**
```
truncate: cannot open '/tmp/build/mount/var/log/dpkg.log' for writing: Permission denied
rm: cannot remove '/tmp/build/mount/var/lib/apt/lists/lock': Permission denied
```

These are **expected and harmless warnings** during image cleanup. The build completes successfully despite these messages, which occur because some files are owned by root in the chroot environment.

You can safely ignore these messages or suppress them by using the updated entrypoint script.

## 🛠️ Development

### Adding Custom Configurations

1. Place files in `configs/network/`, `configs/security/`, etc.
2. Update `containers/builder/scripts/stage2-customize.sh`
3. Rebuild: `docker compose build && docker compose run --rm builder`

### Debugging Builds

```bash
# View detailed logs
tail -f output/build-$(date +%Y%m%d)-*.log

# Interactive debugging
docker compose run --rm builder bash
# Then manually run: /scripts/build.sh
```

### Testing Images

```bash
# Basic functionality test
docker compose run --rm tester

# Manual testing with QEMU
qemu-system-arm -M raspi3 -kernel output/pi-router-*.img
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
- **Base System Caching**: 85% time reduction when `pirouter-rpi3-buster-base-v1.tar.gz` exists

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

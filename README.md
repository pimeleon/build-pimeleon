# Pi Router Build System

A containerized build system for creating Raspberry Pi 3B+ router images with ARM emulation and automated testing.

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

# Build containers (with APT cache optimization)
docker compose build

# Create Pi Router image
docker compose run --rm builder
```

The resulting image will be in `output/pimeleon-YYYYMMDD-HHMMSS.img`

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
- ✅ **ARM Emulation**: Build ARM images on x86 hardware
- ✅ **Build Caching**: Preserves successful base systems (149MB cache)
- ✅ **APT Cache Support**: Uses TrueNAS apt-cacher-ng at 192.168.76.5:3142
- ✅ **systemd-networkd**: Matches production Pi configuration
- ✅ **Security Hardening**: SSH key-only auth, restricted sudo access

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
APT_CACHE_SERVER=192.168.76.5 docker compose build

# Clean Docker caches while preserving base images
./scripts/clean-docker.sh

# Full cleanup (removes everything)
./scripts/clean-docker.sh --full
```

## 📁 Project Structure

```shell
pimeleon-build/
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
│   └── clean-docker.sh             # Selective cache cleanup
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

- **Images**: `output/pimeleon-YYYYMMDD-HHMMSS.img` (4GB bootable image)
- **Logs**: `output/build-YYYYMMDD-HHMMSS.log` (detailed build logs)
- **Credentials**: `output/pi-initial-password.txt` (generated password)

## 🚨 Common Issues & Solutions

### Build Issues

❌ "chroot: failed to run command"

```bash
# Install ARM binary format support on host
sudo apt install binfmt-support qemu-user-static
```

❌ "Permission denied" during configuration

- Fixed: Scripts now use `sudo tee` for proper permissions

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

- Enable APT cache: Builds use TrueNAS apt-cacher-ng automatically
- Base system caching: Successful stage1 cached as `raspbian-buster-base.tar.gz`
- Use SSD storage for better I/O performance

**Out of memory:**

```bash
# Increase Docker memory limit
# In Docker Desktop: Settings > Resources > Memory > 8GB+
```

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

- Debian 12 build container with ARM cross-compilation
- Raspbian Buster base system creation and caching
- Package installation with APT cache support
- Network configuration with systemd-networkd
- User creation and SSH hardening
- Build artifact generation

### 🚧 In Development

- Stage 3: Image optimization and cleanup
- Stage 4: Compression and metadata generation
- Comprehensive test framework
- CI/CD pipeline integration

### 📈 Performance

- **Initial build**: ~45 minutes (includes debootstrap)
- **Cached builds**: ~15 minutes (reuses base system)
- **With APT cache**: ~10 minutes faster package downloads
- **Output size**: 4GB raw image, ~1.5GB compressed

## 📞 Support

- Build issues: Check `output/build-*.log` files
- Permission errors: Ensure proper sudo configuration
- Network problems: Verify APT cache connectivity
- Performance: Use SSD storage and enable caching

The system is actively developed and tested with Raspberry Pi 3B+ hardware running Raspbian Buster.

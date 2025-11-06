# Multi-Platform Support

## Overview

Pi Router Build System supports multiple ARM-based single-board computers (SBCs) through a YAML-based hardware profile system. While Raspberry Pi remains our primary platform with first-class support, the build system can create router images for various ARM hardware.

## Platform Status

### Core Platforms (Maintained by Core Team)

| Platform | Model | Architecture | Status | Maintainer |
|----------|-------|--------------|--------|------------|
| Raspberry Pi | 3 Model B+ | ARMv7 (32-bit) | ✅ Stable | Core Team |
| Raspberry Pi | 4 Model B | ARMv8 (64-bit) | ✅ Stable | Core Team |
| Raspberry Pi | Zero W | ARMv6 (32-bit) | 🚧 Beta | Core Team |
| Orange Pi | 5 Plus | ARMv8 (64-bit) | 🚧 Beta | Core Team |

### Community Platforms

| Platform | Model | Architecture | Status | Maintainer |
|----------|-------|--------------|--------|------------|
| _Add your platform!_ | - | - | - | [Contribution Guide](../contributing/adding-platforms.md) |

**Status Levels**:
- ✅ **Stable**: Production-ready, extensively tested, full support
- 🚧 **Beta**: Functional, documented, regular testing, active support
- 🧪 **Experimental**: Initial support, limited testing, community support only

## Quick Platform Selection

### Choose Based on Your Needs

**Budget-Friendly Router**:
- **Raspberry Pi 3B+**: Best value, proven platform, extensive community
- **Estimated Cost**: ~$35-45 USD

**High-Performance Router**:
- **Orange Pi 5 Plus**: 2.5GbE, 8-core CPU, up to 32GB RAM
- **Estimated Cost**: ~$100-150 USD

**Compact/Low Power**:
- **Raspberry Pi Zero W**: Ultra-compact, low power consumption
- **Estimated Cost**: ~$10-15 USD

**Future-Proof**:
- **Raspberry Pi 4B**: Active development, USB 3.0, dual 4K displays
- **Estimated Cost**: ~$45-75 USD

## Platform Comparison

### Performance Comparison

| Feature | Pi 3B+ | Pi 4B | Pi Zero W | Orange Pi 5+ |
|---------|--------|-------|-----------|--------------|
| CPU Cores | 4 | 4 | 1 | 8 |
| CPU Freq | 1.4 GHz | 1.8 GHz | 1.0 GHz | 2.4 GHz |
| RAM Options | 1GB | 2/4/8GB | 512MB | 4/8/16/32GB |
| Ethernet | 1 Gbps | 1 Gbps | - | 2.5 Gbps |
| WiFi | 2.4/5 GHz | 2.4/5 GHz | 2.4 GHz | WiFi 6 |
| USB Ports | 4x USB 2.0 | 2x USB 3.0, 2x USB 2.0 | 1x micro USB | 2x USB 3.0, 2x USB 2.0 |
| Storage | SD card | SD card | SD card | eMMC / SD card |
| Power Draw | ~2.5W | ~3-6W | ~0.5-1W | ~5-10W |

### Build Performance

| Platform | Build Time (cached) | Build Time (fresh) | Image Size | Boot Time |
|----------|---------------------|-------------------|------------|-----------|
| Pi 3B+ | ~8 min | ~15 min | 3.8 GB | ~60s |
| Pi 4B | ~7 min | ~14 min | 3.9 GB | ~45s |
| Pi Zero W | ~10 min | ~18 min | 3.5 GB | ~90s |
| Orange Pi 5+ | ~10 min | ~17 min | 4.2 GB | ~90s |

### Feature Comparison

| Feature | Pi 3B+ | Pi 4B | Pi Zero W | Orange Pi 5+ |
|---------|--------|-------|-----------|--------------|
| GPIO | ✅ 40-pin | ✅ 40-pin | ✅ 40-pin | ✅ 40-pin |
| UART | ✅ | ✅ | ✅ | ✅ |
| SPI | ✅ | ✅ | ✅ | ⚠️ Limited |
| I2C | ✅ | ✅ | ✅ | ⚠️ Limited |
| Camera | ✅ CSI | ✅ CSI | ✅ CSI | ✅ MIPI CSI |
| Display | ✅ DSI | ✅ DSI | ✅ mini HDMI | ✅ HDMI 2.1 |
| Audio | ✅ 3.5mm | ✅ 3.5mm | ✅ mini HDMI | ✅ HDMI |
| Bluetooth | ✅ BT 4.2 | ✅ BT 5.0 | ✅ BT 4.1 | ✅ BT 5.0 |

## Getting Started with a Platform

### 1. Choose Your Platform

Select a platform based on your requirements (see comparison tables above).

### 2. Build an Image

```bash
# Raspberry Pi 3B+ (default)
make build

# Raspberry Pi 4B
PIMELEON_PLATFORM=raspberrypi PIMELEON_MODEL=4B make build

# Orange Pi 5 Plus
PIMELEON_PLATFORM=orangepi PIMELEON_MODEL=5-plus make build
```

### 3. Flash to Storage

```bash
# Find your device
lsblk

# Flash image (replace /dev/sdX with your device)
sudo dd if=output/pimeleon-*.img of=/dev/sdX bs=4M status=progress
sudo sync
```

### 4. Boot and Configure

Insert storage media, power on, and access via SSH:

```bash
# Default credentials
ssh pi@<device-ip>
# Password: (see output/pi-initial-password.txt)
```

## Platform-Specific Documentation

### Raspberry Pi
- [Raspberry Pi 3B+ Guide](raspberrypi/3b-plus.md)
- [Raspberry Pi 4B Guide](raspberrypi/4b.md)
- [Raspberry Pi Zero W Guide](raspberrypi/zero-w.md)

### Orange Pi
- [Orange Pi 5 Plus Guide](orangepi/5-plus.md)

### Community Platforms
- [Browse Community Platforms](community/)
- [Contribute a Platform](../contributing/adding-platforms.md)

## Hardware Abstraction

The multi-platform support is implemented through:

1. **Hardware Profiles**: YAML files describing platform specifications
2. **Boot Templates**: Jinja2 templates for bootloader configuration
3. **Platform Hooks**: Optional scripts for platform-specific build steps
4. **Conditional Logic**: Build stages adapt based on profile data

See [Multi-Platform Architecture](../architecture/multi-platform-strategy.md) for technical details.

## Contributing a New Platform

We welcome community contributions of new platforms!

**Prerequisites**:
- ARM-based SBC (32-bit or 64-bit)
- Access to physical hardware for testing
- Basic understanding of Linux boot process

**Process**:
1. Read the [Contributing Platforms Guide](../contributing/adding-platforms.md)
2. Create hardware profile YAML
3. Add boot configuration template
4. Test on real hardware
5. Submit pull request

**Support**: Join our community discussions for help with platform contributions.

## Platform Maintainers

### How to Become a Maintainer

Platform maintainers are community members who commit to maintaining support for specific hardware platforms.

**Requirements**:
- Successfully contribute a working platform
- Commit to 6+ months of maintenance
- Respond to platform-specific issues within 2 weeks
- Keep profile updated with OS/package changes

**Benefits**:
- Recognition in documentation and community
- Platform maintainer badge
- Direct input on platform features
- Optional write access to platform directory

**Apply**: Submit a platform contribution and indicate maintainer interest in your PR.

## Frequently Asked Questions

### Can I use Pi Router on non-ARM hardware?

Currently, Pi Router Build System targets ARM platforms only. x86/x64 support would require significant architectural changes.

### What's the difference between platforms?

Each platform has different hardware capabilities (CPU, RAM, network), bootloaders (U-Boot vs Pi firmware), and OS requirements (Raspbian vs Debian vs Armbian). The profile system handles these differences automatically.

### Which platform is recommended?

For most users, **Raspberry Pi 4B** offers the best balance of performance, compatibility, and cost. For budget builds, **Pi 3B+** is excellent. For high-performance needs, consider **Orange Pi 5 Plus**.

### Can I build for multiple platforms at once?

Yes! Use CI/CD platform matrix or run builds sequentially:

```bash
for model in 3B+ 4B; do
  PIMELEON_PLATFORM=raspberrypi PIMELEON_MODEL=$model make build
done
```

### How do I report platform-specific issues?

Create a GitHub issue with the `platform:` label and tag the platform maintainer.

## Roadmap

### Near-Term (3 months)
- ✅ Raspberry Pi 3B+, 4B (Stable)
- 🚧 Orange Pi 5 Plus (Beta)
- 📝 Rock Pi 4B (Planned)

### Mid-Term (6 months)
- Nano Pi support
- Automated hardware compatibility testing
- Platform status dashboard

### Long-Term (12 months)
- 10+ community-maintained platforms
- Plugin architecture for platform extensions
- Cross-platform feature parity

## Resources

### Documentation
- [Multi-Platform Strategy](../architecture/multi-platform-strategy.md)
- [Hardware Profiles Reference](../architecture/hardware-profiles.md)
- [Migration Roadmap](../architecture/migration-roadmap.md)
- [Contributing Guide](../contributing/adding-platforms.md)

### Community
- [GitHub Discussions](https://github.com/yourorg/pimeleon-build/discussions)
- [GitHub Issues](https://github.com/yourorg/pimeleon-build/issues)
- [Platform Maintainers Chat](https://discord.gg/yourserver)

### External Resources
- [Raspberry Pi Documentation](https://www.raspberrypi.com/documentation/)
- [Orange Pi Resources](http://www.orangepi.org/)
- [Armbian Documentation](https://docs.armbian.com/)

---

**Last Updated**: 2025-01-06
**Maintained By**: Pi Router Core Team

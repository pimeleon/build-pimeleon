# Supported Platforms

## Overview

Pi Router Build System supports Raspberry Pi single-board computers through a YAML-based hardware profile system. The build system creates custom router images optimized for each supported model.

## Supported Platforms

| Platform | Model | Architecture | Status | Maintainer |
|----------|-------|--------------|--------|------------|
| Raspberry Pi | 3 Model B+ | ARMv7 (32-bit) | ✅ Stable | Core Team |
| Raspberry Pi | 4 Model B | ARMv8 (64-bit) | ✅ Stable | Core Team |

**Status Levels**:
- ✅ **Stable**: Production-ready, extensively tested, full support

## Quick Platform Selection

### Raspberry Pi 3B+ (Recommended for most users)
- **Best for**: Budget-friendly router, proven platform
- **Estimated Cost**: ~$35-45 USD
- **Throughput**: ~300 Mbps (Ethernet over USB 2.0)

### Raspberry Pi 4B (High Performance)
- **Best for**: Gigabit throughput, future-proof builds
- **Estimated Cost**: ~$45-75 USD
- **Throughput**: ~940 Mbps (true Gigabit Ethernet)

## Platform Comparison

### Hardware Specifications

| Feature | Pi 3B+ | Pi 4B |
|---------|--------|-------|
| CPU Cores | 4 | 4 |
| CPU Freq | 1.4 GHz | 1.8 GHz |
| RAM Options | 1GB | 2/4/8GB |
| Ethernet | 1 Gbps* | 1 Gbps |
| WiFi | 2.4/5 GHz | 2.4/5 GHz |
| USB Ports | 4x USB 2.0 | 2x USB 3.0, 2x USB 2.0 |
| Power Draw | ~2.5W | ~3-6W |

*Pi 3B+ Ethernet is limited to ~300 Mbps due to USB 2.0 bus

### Build Performance

| Platform | Build Time (cached) | Build Time (fresh) | Image Size |
|----------|---------------------|-------------------|------------|
| Pi 3B+ | ~8 min | ~15 min | 3.8 GB |
| Pi 4B | ~7 min | ~14 min | 3.9 GB |

## Building Images

### Raspberry Pi 3B+ (Default)

```bash
export DOCKER_BUILDKIT=1 && docker compose run --rm builder

# Or explicitly:
export DOCKER_BUILDKIT=1 && \
  PIMELEON_RPI_MODEL=3B+ \
  docker compose run --rm builder
```

### Raspberry Pi 4B

```bash
export DOCKER_BUILDKIT=1 && \
  PIMELEON_RPI_MODEL=4B \
  docker compose run --rm builder
```

## Platform Documentation

- [Raspberry Pi 3B+ Guide](raspberrypi/3b-plus.md)
- [Raspberry Pi 4B Guide](raspberrypi/4b.md)

## Flashing Images

```bash
# Find your SD card device
lsblk

# Flash image (replace /dev/sdX with your device)
sudo dd if=output/pimeleon-*.img of=/dev/sdX bs=4M status=progress
sudo sync
```

## First Boot

Insert SD card, power on, and access via SSH:

```bash
ssh pi@<device-ip>
# Password: see output/pi-initial-password.txt
```

## Future Platform Support

See [Multi-Platform Strategy](../architecture/multi-platform-strategy.md) for the roadmap on expanding platform support to additional ARM SBCs.

---

**Last Updated**: 2025-01-06
**Maintained By**: Pi Router Core Team

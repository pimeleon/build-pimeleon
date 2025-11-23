# Pimeleon Build System

<div class="grid cards" markdown>

-   :material-rocket-launch:{ .lg .middle } __Quick Start__

    ---

    Get your first Pimeleon image built in minutes

    [:octicons-arrow-right-24: Getting Started](getting-started/index.md)

-   :material-book-open-variant:{ .lg .middle } __User Guides__

    ---

    Learn how to build, customize, and optimize your Pimeleon images

    [:octicons-arrow-right-24: View Guides](guides/building-images.md)

-   :material-cube-outline:{ .lg .middle } __Architecture__

    ---

    Understand the container-based build system and pipeline

    [:octicons-arrow-right-24: Architecture Overview](architecture/overview.md)

-   :material-code-tags:{ .lg .middle } __Reference__

    ---

    Complete CLI, configuration, and API reference

    [:octicons-arrow-right-24: Reference Docs](reference/cli-commands.md)

-   :material-devices:{ .lg .middle } __Multi-Platform__

    ---

    Support for multiple ARM SBCs with hardware profiles

    [:octicons-arrow-right-24: Platform Documentation](platforms/README.md)

</div>

## Overview

The **Pimeleon Build System** is a containerized, Docker-based ARM cross-compilation environment for creating custom Raspberry Pi router images. It automates the entire process of building bootable SD card images with networking, security, and routing capabilities pre-configured.

### Key Features

- :fontawesome-solid-microchip: **ARM Emulation** - Build ARM images on x86 hardware using QEMU user-mode emulation
- :fontawesome-solid-layer-group: **Multi-Stage Pipeline** - Automated 4-stage build process (base, customize, optimize, package)
- :fontawesome-brands-raspberry-pi: **Complete Pi Firmware** - Includes bootcode.bin, start.elf, kernels for Pi 3B+
- :fontawesome-solid-gauge-high: **Smart Caching** - Hardware-specific base system caching for 85% faster rebuilds
- :fontawesome-solid-network-wired: **Production Networking** - systemd-networkd with bonding, DHCP, WiFi AP, firewall
- :fontawesome-solid-shield-halved: **Security Hardening** - SSH key-only auth, fail2ban, automatic updates, audit logging
- :fontawesome-solid-bolt: **APT Cache Support** - Optional apt-cacher-ng integration for 48% faster builds
- :fontawesome-solid-vial: **Automated Testing** - QEMU-based integration and security testing

### What You Get

The build system produces:

- **Bootable 4GB SD card images** ready to flash to Raspberry Pi 3B+
- **Pre-configured networking**: WAN (DHCP), LAN (static), WiFi AP
- **Routing & NAT**: Full IPv4/IPv6 forwarding with nftables firewall
- **DHCP & DNS**: ISC DHCP server and DNS resolution
- **Security**: Hardened SSH, fail2ban, automatic security updates
- **Management access**: SSH accessible via management interface

### Build Performance

| Metric | Without Cache | With APT Cache | With Base Cache |
|--------|---------------|----------------|-----------------|
| **Initial Build** | 19:49 | 10:12 | 10:12 |
| **Rebuild** | 19:49 | 10:12 | 5-8 min |
| **Cache Hit Rate** | 0% | 95% | 85% |
| **Time Saved** | - | 48.5% | 85% |

### Supported Hardware

Currently supports:

- **Raspberry Pi 3B+** (primary target, stable)
- **Raspberry Pi 4B** (planned)
- **Orange Pi 5 Plus** (planned, proof-of-concept)
- **Community platforms** (contribution framework ready)

[:octicons-arrow-right-24: View Platform Comparison](platforms/README.md)

### Technology Stack

```mermaid
graph LR
    A[Docker BuildKit] --> B[Debian 12 Builder]
    B --> C[QEMU ARM Emulation]
    C --> D[Debootstrap]
    D --> E[Raspbian Buster]
    E --> F[Ansible Provisioning]
    F --> G[Bootable Image]

    H[APT Cache] -.->|Optional| D
    I[Base Cache] -.->|85% speedup| E
```

### Quick Example

```bash title="Build a Pimeleon Image"
# Build with APT cache support
export DOCKER_BUILDKIT=1
export APT_PROXY=192.168.76.5:3142

docker compose run --rm builder
```

```bash title="Result"
✓ Stage 1: Base system created (149MB cache)
✓ Stage 2: Packages installed and configured
✓ Output: output/pimeleon-20241102-103045.img (4GB)
✓ Build time: 10:12 (with APT cache)
```

### Project Status

| Component | Status | Notes |
|-----------|--------|-------|
| Stage 1: Base System | ✅ Complete | Raspbian Buster bootstrap |
| Stage 2: Customization | ✅ Complete | Ansible provisioning |
| Stage 3: Optimization | 🔄 Implemented | Disabled for rapid iteration |
| Stage 4: Packaging | 🔄 Implemented | Disabled for rapid iteration |
| Testing Framework | 🔄 In Progress | Basic tests working |
| CI/CD Pipeline | ✅ Complete | GitHub Actions configured |

---

## Next Steps

<div class="grid cards" markdown>

-   **New to the project?**

    Start with the [Prerequisites](getting-started/prerequisites.md) and [First Build](getting-started/first-build.md) guides

-   **Ready to customize?**

    Check out the [Customization Guide](guides/customization.md) and [Configuration Reference](reference/configuration-files.md)

-   **Want to contribute?**

    See the [Development Setup](contributing/development.md) and [Testing Guide](contributing/testing.md)

-   **Adding a new platform?**

    Check out the [Multi-Platform Strategy](architecture/multi-platform-strategy.md) and [Platform Contribution Guide](contributing/adding-platforms.md)

</div>

## Support

- **Documentation**: [https://docs.pimeleon.com](https://docs.pimeleon.com)
- **Repository**: [GitHub](https://github.com/yourusername/pimeleon)
- **Issues**: [GitHub Issues](https://github.com/yourusername/pimeleon/issues)

---

*Built with :material-heart: using Docker, QEMU, Ansible, and MkDocs Material*

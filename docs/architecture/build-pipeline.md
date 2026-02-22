# Build Pipeline

The Pimeleon build pipeline is a containerized, 4-stage process designed to create
consistent, reproducible, and optimized Raspberry Pi images.

## Stage 1: Base System Bootstrap

The first stage creates the initial Raspbian/Debian root filesystem using `debootstrap`.

- **Tools**: `debootstrap`, `qemu-arm-static`.
- **Outputs**: A raw partition layout and a minimal root filesystem.
- **Caching**: The resulting root filesystem is tarballed and cached (`cache/pimeleon-*-base.tar.gz`)
  to accelerate subsequent builds. This stage is skipped if a valid cache exists.

## Stage 2: Customization

In this stage, the base system is customized with Pimeleon-specific software and configurations.

- **Tools**: `ansible`, `chroot`.
- **Actions**:
  - **Package Installation**: Installs essential services (hostapd, dnsmasq, nftables, etc.).
  - **System Configuration**: Sets hostname, timezones, and systemd-networkd rules.
  - **User Management**: Creates the default 'pi' user with secure SSH access.
  - **Ansible Playbooks**: Executes the project's Ansible playbooks directly within the ARM chroot.
- **Network**: Uses the internal `build-network` to isolate the build from the host.

## Stage 3: Optimization

This stage performs post-customization optimizations to reduce the image size and improve performance.

- **Status**: Currently disabled by default in `build.sh` for faster development cycles.
- **Actions**:
  - Removing build-only dependencies.
  - Clearing package caches.
  - Zeroing out free space for better compression.

## Stage 4: Packaging

The final stage prepares the image for distribution.

- **Status**: Currently disabled by default in `build.sh`.
- **Actions**:
  - **Compression**: Compresses the raw `.img` file using `xz`.
  - **Metadata**: Generates `metadata.json` with versioning and checksum information.
  - **Checksums**: Creates SHA256 checksums for all distribution artifacts.

---

For more information on how this pipeline is integrated into the automated infrastructure,
see the [CI/CD Infrastructure](cicd.md) documentation.

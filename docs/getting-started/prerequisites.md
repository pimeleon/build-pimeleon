# Prerequisites

Before building Pimeleon images, ensure your system meets the following requirements.

## Hardware Requirements

### Minimum Specifications

| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|-------|
| **CPU** | 4 cores | 8 cores | Parallel builds benefit from more cores |
| **RAM** | 8 GB | 16 GB | Docker and QEMU require significant memory |
| **Disk Space** | 50 GB free | 100 GB free | Includes Docker images, build cache, output |
| **Disk Type** | HDD | SSD | SSD dramatically improves I/O performance |
| **Network** | 10 Mbps | 100+ Mbps | For downloading packages (first build) |

!!! tip "Storage Breakdown"
    - Docker images: ~5 GB
    - Build workspace: ~10 GB
    - APT cache (optional): ~2 GB
    - Base system cache: ~150 MB
    - Output images: ~4 GB per image
    - Recommended headroom: 30+ GB

## Software Requirements

### Operating System

**Supported:**

- ✅ Ubuntu 22.04 LTS or newer
- ✅ Debian 12 (Bookworm) or newer
- ✅ Fedora 38 or newer
- ✅ Other Linux distributions with kernel 5.10+

**Not Supported:**

- ❌ Windows (even with WSL2) - ARM emulation issues
- ❌ macOS - Limited QEMU support, performance issues
- ❌ Old Linux kernels (< 5.0)

!!! warning "WSL2 Limitations"
    While WSL2 technically works, ARM emulation performance is poor and builds may fail
    randomly. Native Linux is strongly recommended.

### Docker

**Required Version:** Docker 24.0 or newer with BuildKit support

#### Installation

=== "Ubuntu/Debian"

    ```bash
    # Remove old versions
    sudo apt remove docker docker-engine docker.io containerd runc

    # Install dependencies
    sudo apt update
    sudo apt install ca-certificates curl gnupg lsb-release

    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    # Set up repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    sudo apt update
    sudo apt install docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin

    # Add your user to docker group
    sudo usermod -aG docker $USER
    newgrp docker  # Or log out and back in
    ```

=== "Fedora"

    ```bash
    # Install Docker
    sudo dnf install docker docker-compose-plugin

    # Start Docker service
    sudo systemctl start docker
    sudo systemctl enable docker

    # Add user to docker group
    sudo usermod -aG docker $USER
    newgrp docker
    ```

=== "Other Linux"

    See [Docker's official installation guide](https://docs.docker.com/engine/install/)

#### Verify Installation

```bash
# Check Docker version
docker --version
# Output: Docker version 24.0.0 or higher

# Check BuildKit support
docker buildx version
# Should show buildx version

# Check compose plugin
docker compose version
# Should show compose version

# Test Docker
docker run hello-world
```

### ARM Binary Format Support

**Required:** QEMU user-mode emulation and binfmt support

This allows running ARM binaries on x86 hosts, which is essential for the build process.

#### Installation

```bash
sudo apt update
sudo apt install binfmt-support qemu-user-static
```

#### Verify Installation

```bash
# Check if ARM emulation is registered
ls -la /proc/sys/fs/binfmt_misc/qemu-arm*

# You should see files like:
# qemu-arm
# qemu-aarch64

# Test ARM emulation
docker run --rm arm32v7/alpine uname -m
# Output: armv7l
```

!!! info "How It Works"
    The `binfmt-support` package registers ARM binary formats with the kernel, and
    `qemu-user-static` provides the ARM emulator. When you try to run an ARM binary on x86,
    the kernel automatically invokes QEMU to execute it.

### Git

Required for cloning the repository and version control.

```bash
# Install Git
sudo apt install git

# Verify installation
git --version
```

## Optional But Recommended

### APT Caching Proxy

An APT caching proxy like `apt-cacher-ng` dramatically speeds up builds by caching downloaded packages.

**Benefits:**

- 48.5% faster builds (10 min vs 19 min)
- 95%+ cache hit rate on subsequent builds
- Reduces bandwidth usage
- Useful for multiple build machines

#### Setting Up apt-cacher-ng

=== "Dedicated Server"

    On a server accessible from your build machine:

    ```bash
    # Install apt-cacher-ng
    sudo apt install apt-cacher-ng

    # Start service
    sudo systemctl start apt-cacher-ng
    sudo systemctl enable apt-cacher-ng

    # Configure to cache Raspbian (optional)
    echo "Remap-debrep: file:debian_raspbian.conf /raspbian/" | \
      sudo tee -a /etc/apt-cacher-ng/acng.conf

    sudo systemctl restart apt-cacher-ng
    ```

    Then use `APT_PROXY=<server-ip>:3142` when building.

=== "Docker Container"

    Run apt-cacher-ng in a container:

    ```bash
    docker run -d \
      --name apt-cacher-ng \
      --restart always \
      -p 3142:3142 \
      -v apt-cacher-data:/var/cache/apt-cacher-ng \
      sameersbn/apt-cacher-ng:latest
    ```

    Use `APT_PROXY=host.docker.internal:3142` or your host IP with port.

=== "Skip It"

    You can skip APT caching entirely. Builds will just take longer (~20 min vs ~10 min).

### Make

The project includes a Makefile for convenience. Install `make`:

```bash
sudo apt install make

# Verify
make --version
```

### Text Editor

For editing configuration files. Any of these work:

- `vim` / `nano` (terminal-based)
- VS Code with Docker extension
- JetBrains IDEs

## Verification Checklist

Run these commands to verify your system is ready:

```bash title="System Verification Script"
#!/bin/bash

echo "=== Pimeleon Build System Prerequisites Check ==="
echo

# Docker version
echo "✓ Checking Docker..."
docker --version || echo "✗ Docker not found"

# Docker BuildKit
echo "✓ Checking BuildKit..."
docker buildx version || echo "✗ BuildKit not found"

# Docker Compose
echo "✓ Checking Docker Compose..."
docker compose version || echo "✗ Docker Compose not found"

# Disk space
echo "✓ Checking disk space..."
df -h /var/lib/docker | tail -1 | awk '{print $4 " available"}'

# Memory
echo "✓ Checking memory..."
free -h | grep "Mem:" | awk '{print $2 " total RAM"}'

# ARM emulation
echo "✓ Checking ARM emulation..."
ls /proc/sys/fs/binfmt_misc/qemu-arm* 2>/dev/null && \
  echo "ARM emulation registered" || \
  echo "✗ ARM emulation not found"

# Git
echo "✓ Checking Git..."
git --version || echo "✗ Git not found"

# Make (optional)
echo "✓ Checking Make (optional)..."
make --version >/dev/null 2>&1 && echo "Make installed" || echo "Make not found (optional)"

echo
echo "=== Check Complete ==="
```

Save as `check-prereqs.sh`, make executable with `chmod +x check-prereqs.sh`, and run:

```bash
./check-prereqs.sh
```

## Common Issues

### Docker Permission Denied

**Symptom:**

```
permission denied while trying to connect to the Docker daemon socket
```

**Solution:**

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in, or run:
newgrp docker
```

### ARM Emulation Not Working

**Symptom:**

```
exec user process caused: exec format error
```

**Solution:**

```bash
# Reinstall QEMU and binfmt
sudo apt install --reinstall binfmt-support qemu-user-static

# Restart Docker
sudo systemctl restart docker
```

### Insufficient Disk Space

**Symptom:**

```
no space left on device
```

**Solution:**

```bash
# Clean Docker system
docker system prune -a

# Check space
df -h /var/lib/docker

# Consider moving Docker data directory if needed
```

## Next Steps

Once you've verified all prerequisites:

1. [Clone the repository and build your first image](first-build.md)
2. [Learn about customization options](../guides/customization.md)
3. [Understand the build system architecture](../architecture/overview.md)

---

!!! question "Still having issues?"
    Check the [Troubleshooting Guide](../guides/troubleshooting.md) or [open an issue](https://github.com/yourusername/pimeleon/issues).

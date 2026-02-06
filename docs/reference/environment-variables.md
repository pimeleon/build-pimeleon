# Environment Variables

Complete reference for all configuration environment variables.

## Build Configuration

### Platform Selection

| Variable | Default | Description |
|----------|---------|-------------|
| `PIMELEON_RPI_MODEL` | `3B+` | Target Raspberry Pi model (`3B+`, `4B`) |
| `PIMELEON_IMAGE_SIZE` | `4G` | Output image size (`4G`, `8G`, `16G`) |
| `PIMELEON_INITIAL_PASSWORD` | `netblox` | Initial password for `pi` user |

### Debian Version

| Variable | Default | Description |
|----------|---------|-------------|
| `RASPBIAN_VERSION` | `bullseye` | Debian version to use |

**Supported versions:**

| Version | Codename | Status | Notes |
|---------|----------|--------|-------|
| 11 | `bullseye` | Default | Current stable |
| 12 | `bookworm` | Supported | Current stable |
| 13 | `trixie` | Testing | Not yet released |

### Build System

| Variable | Default | Description |
|----------|---------|-------------|
| `DOCKER_BUILDKIT` | `1` | Enable Docker BuildKit (required) |
| `RASPBIAN_MIRROR` | `http://archive.raspbian.org/raspbian/` | APT mirror URL |

## Caching Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `APT_CACHE_SERVER` | *(none)* | APT cache server IP (e.g., `192.168.42.5`) |
| `APT_CACHE_PORT` | `3142` | APT cache port (apt-cacher-ng default) |

## Usage Examples

### Basic Build (Pi 3B+, Bullseye)

```bash
docker compose run --rm builder
```

### Pi 4 with Bookworm

```bash
PIMELEON_RPI_MODEL=4B RASPBIAN_VERSION=bookworm docker compose run --rm builder
```

### Pi 3B+ with Bullseye and APT Cache

```bash
PIMELEON_RPI_MODEL=3B+ \
RASPBIAN_VERSION=bullseye \
APT_CACHE_SERVER=192.168.42.5 \
docker compose run --rm builder
```

### Full Configuration

```bash
export DOCKER_BUILDKIT=1
PIMELEON_RPI_MODEL=4B \
PIMELEON_IMAGE_SIZE=8G \
PIMELEON_INITIAL_PASSWORD=mysecurepass \
RASPBIAN_VERSION=bookworm \
APT_CACHE_SERVER=192.168.42.5 \
docker compose run --rm builder
```

## Ansible Variable Mapping

Environment variables are passed to Ansible playbooks:

| Environment Variable | Ansible Variable | Group Vars File |
|---------------------|------------------|-----------------|
| `PIMELEON_RPI_MODEL` | `platform_model` | `all/main.yml` |
| `RASPBIAN_VERSION` | `debian_version` | `all/main.yml` |
| `PIMELEON_INITIAL_PASSWORD` | `pimeleon_initial_password` | `all/main.yml` |

Platform-specific variables are loaded from `ansible/inventory/group_vars/`:

- `all/` - Global defaults
- `raspberrypi/` - Pi family defaults
- `raspberrypi_3bplus/` - Pi 3B+ specific
- `raspberrypi_4b/` - Pi 4B specific

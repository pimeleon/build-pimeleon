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
| `RASPBIAN_MIRROR` | `http://mirrordirector.raspbian.org/raspbian/` | APT mirror URL |

## Caching Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `APT_PROXY` | *(none)* | APT proxy server (`host:port`, e.g., `192.168.76.5:3142`) |

## CI/CD Variables

These variables are primarily used in the GitLab and GitHub automated pipelines.

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_PLATFORM` | *(none)* | Combined platform/version slug (e.g., `rpi3-bookworm`) |
| `PIMELEON_VERSION` | `v1.0.0` | Semantic version of the image being built |
| `BUILD_IMAGE` | *(none)* | Full tag for the builder Docker image |
| `TEST_IMAGE` | *(none)* | Full tag for the tester Docker image |
| `APT_PROXY` | *(none)* | Combined APT cache IP:PORT (e.g., `192.168.76.5:3142`) |

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
APT_PROXY=192.168.76.5:3142 \
docker compose run --rm builder
```

### Full Configuration

```bash
export DOCKER_BUILDKIT=1
PIMELEON_RPI_MODEL=4B \
PIMELEON_IMAGE_SIZE=8G \
PIMELEON_INITIAL_PASSWORD=mysecurepass \
RASPBIAN_VERSION=bookworm \
APT_PROXY=192.168.76.5:3142 \
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

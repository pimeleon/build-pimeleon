# Pi Router Containerized Build System

A containerized build and test system for creating Raspberry Pi Router images with automated testing infrastructure.

## Overview

This build system provides:

- Automated Raspberry Pi Router image creation
- Containerized build environment with ARM emulation
- Comprehensive testing infrastructure using QEMU/KVM
- Multi-stage build pipeline with caching
- Security hardening and validation
- CI/CD integration support

## Requirements

### Minimum System Requirements

- CPU: 4 cores
- RAM: 8GB
- Storage: 50GB
- Docker 24.0+ or Podman 4.0+
- KVM support (optional but recommended)

### Recommended System Requirements

- CPU: 8 cores
- RAM: 16GB
- Storage: 100GB SSD
- KVM enabled for better performance

## Quick Start

1. Clone the repository:

```bash
git clone <repository-url>
cd pimeleon-build
```

1. Build the containers:

```bash
docker-compose build
```

1. Run a full build:

```bash
docker-compose run builder
```

1. Test the generated image:

```bash
docker-compose run tester
```

## Project Structure

```shell
pimeleon-build/
├── .devcontainer/          # VS Code development container
├── containers/
│   ├── builder/           # Build container configuration
│   └── tester/            # Test container with libvirt/QEMU
├── ansible/               # Configuration management
│   ├── playbooks/         # Ansible playbooks
│   ├── roles/             # Ansible roles
│   └── inventory/         # Inventory files
├── tests/                 # Test suites
│   ├── unit/              # Unit tests
│   ├── integration/       # Integration tests
│   └── fixtures/          # Test fixtures
├── configs/               # Pi Router configurations
│   ├── network/           # Network configurations
│   ├── security/          # Security policies
│   └── services/          # Service configurations
├── output/                # Generated images
├── cache/                 # Build cache
└── docker-compose.yml     # Main orchestration file
```

## Build Pipeline

The build process consists of four stages:

1. **Base System** - Bootstrap Raspbian Lite base system
2. **Customization** - Install packages and apply configurations
3. **Optimization** - Clean up and shrink the image
4. **Packaging** - Create final compressed image with metadata

## Testing

The system includes comprehensive testing scenarios:

- **Smoke Test** (5 min) - Basic boot and network validation
- **Integration Test** (15 min) - Service functionality testing
- **Stress Test** (30 min) - Performance and stability testing
- **Security Test** (20 min) - Security validation and hardening

## Development

For development with VS Code:

```shell
code .
# Reopen in container when prompted
```

## CI/CD Integration

The system supports CI/CD pipelines with stages for:

- Linting and validation
- Image building
- Automated testing
- Security scanning
- Artifact publishing

## License

[Specify your license here]

# Testing Guide

This guide covers how to run and create tests for the Pimeleon build system.

## Overview

Pimeleon uses a multi-layered testing strategy to ensure image quality and service
functionality:

1. **Linting**: Static analysis of shell scripts, Ansible playbooks, and YAML files.
2. **Unit Tests**: Validation of configuration file generation and image structure.
3. **Integration Tests**: End-to-end verification using QEMU system emulation to boot the
    generated image and test services.

## Running Tests

### Using the Makefile

The simplest way to run tests is via the provided `Makefile` targets:

```bash
# Run all tests (smoke + integration + security)
make test

# Run quick smoke tests (~5 min)
make test-smoke

# Run service integration tests (~15 min)
make test-integration
```

### Running Manually

You can also run tests directly using `pytest` inside the tester container:

```bash
# Open a shell in the tester container
docker compose run --rm tester bash

# Run all tests
pytest /tests
```

## Test Structure

Tests are located in the `tests/` directory:

- `tests/unit/`: Unit tests for build scripts and configuration logic.
- `tests/integration/`: Integration tests that run against a booted image in QEMU.

## Adding New Tests

### Integration Tests

Integration tests use `pytest` and `testinfra` to verify the state of the booted
system.

Example test (`tests/integration/test_example.py`):

```python
def test_ssh_service(host):
    """Verify that SSH service is running and enabled."""
    ssh = host.service("ssh")
    assert ssh.is_running
    assert ssh.is_enabled

def test_config_file(host):
    """Verify that a specific config file exists and has correct permissions."""
    conf = host.file("/etc/ssh/sshd_config")
    assert conf.exists
    assert conf.user == "root"
    assert conf.mode == 0o644
```

## Continuous Integration

Tests are automatically executed in the GitLab CI/CD pipeline on every push to
`develop` and `release/*` branches. See [CI/CD Infrastructure](../architecture/cicd.md)
for more details.

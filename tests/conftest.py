"""
Pytest configuration and shared fixtures for Pimeleon tests.

Provides fixtures for:
- Mounted image inspection (unit tests)
- Running VM with testinfra (integration tests)
"""

import os
import subprocess
import tempfile
import time
import logging
from pathlib import Path
from contextlib import contextmanager

import pytest

logger = logging.getLogger(__name__)

# Environment configuration
IMAGE_PATH = os.environ.get("TEST_IMAGE_PATH", "/output/pimeleon.img")
VM_SSH_HOST = os.environ.get("VM_SSH_HOST", "172.16.0.1")
VM_SSH_USER = os.environ.get("VM_SSH_USER", "pim")
VM_SSH_PASSWORD = os.environ.get("VM_SSH_PASSWORD", "")
VM_BOOT_TIMEOUT = int(os.environ.get("VM_BOOT_TIMEOUT", "300"))


def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line("markers", "unit: Fast tests on mounted image")
    config.addinivalue_line("markers", "integration: Tests requiring running VM")
    config.addinivalue_line("markers", "smoke: Quick sanity checks")
    config.addinivalue_line("markers", "network: Network configuration tests")
    config.addinivalue_line("markers", "security: Security validation tests")


@contextmanager
def mount_image_partition(image_path: str, partition: int = 2):
    """
    Mount an image partition temporarily.

    Args:
        image_path: Path to the .img file
        partition: Partition number (1=boot, 2=root)

    Yields:
        Path to the mount point
    """
    mount_point = tempfile.mkdtemp(prefix="pimeleon-test-")
    loop_dev = None

    try:
        # Create loop device with partitions
        result = subprocess.run(
            ["losetup", "-f", "--show", "-P", image_path],
            capture_output=True,
            text=True,
            check=True,
        )
        loop_dev = result.stdout.strip()
        logger.info(f"Created loop device: {loop_dev}")

        # Mount the partition
        partition_dev = f"{loop_dev}p{partition}"
        subprocess.run(
            ["mount", partition_dev, mount_point],
            check=True,
        )
        logger.info(f"Mounted {partition_dev} at {mount_point}")

        yield mount_point

    finally:
        # Cleanup
        try:
            subprocess.run(["umount", mount_point], check=False)
        except Exception:
            pass

        if loop_dev:
            try:
                subprocess.run(["losetup", "-d", loop_dev], check=False)
            except Exception:
                pass

        try:
            os.rmdir(mount_point)
        except Exception:
            pass


@pytest.fixture(scope="session")
def image_path():
    """Path to the Pimeleon image under test."""
    path = Path(IMAGE_PATH)
    if not path.exists():
        pytest.skip(f"Image not found: {IMAGE_PATH}")
    return path


@pytest.fixture(scope="session")
def mounted_root(image_path):
    """
    Mount the root partition of the image for inspection.

    This fixture mounts the root filesystem (partition 2) and yields
    the mount point path. Cleanup is automatic.
    """
    with mount_image_partition(str(image_path), partition=2) as mount_point:
        yield Path(mount_point)


@pytest.fixture(scope="session")
def mounted_boot(image_path):
    """
    Mount the boot partition of the image for inspection.

    This fixture mounts the boot filesystem (partition 1) and yields
    the mount point path. Cleanup is automatic.
    """
    with mount_image_partition(str(image_path), partition=1) as mount_point:
        yield Path(mount_point)


@pytest.fixture(scope="session")
def vm_host():
    """
    Get a testinfra host connected to the running VM.

    Requires:
    - VM to be already running (via test-integration.sh or manual)
    - SSH access configured
    - VM_SSH_PASSWORD environment variable set
    """
    try:
        import testinfra
    except ImportError:
        pytest.skip("testinfra not installed")

    if not VM_SSH_PASSWORD:
        pytest.skip("VM_SSH_PASSWORD not set")

    # Wait for VM to be reachable
    logger.info(f"Waiting for VM at {VM_SSH_HOST}...")
    start_time = time.time()

    while time.time() - start_time < VM_BOOT_TIMEOUT:
        try:
            result = subprocess.run(
                ["ping", "-c", "1", "-W", "2", VM_SSH_HOST],
                capture_output=True,
            )
            if result.returncode == 0:
                logger.info("VM is reachable")
                break
        except Exception:
            pass
        time.sleep(5)
    else:
        pytest.skip(f"VM not reachable after {VM_BOOT_TIMEOUT}s")

    # Create testinfra host
    host = testinfra.get_host(
        f"paramiko://{VM_SSH_USER}@{VM_SSH_HOST}",
        ssh_config={
            "password": VM_SSH_PASSWORD,
            "StrictHostKeyChecking": "no",
            "UserKnownHostsFile": "/dev/null",
        },
    )

    return host


@pytest.fixture
def expected_services():
    """List of services that should be enabled and running."""
    return [
        "systemd-networkd",
        "systemd-resolved",
        "ssh",
        "dnsmasq",
    ]


@pytest.fixture
def expected_users():
    """Users that should exist on the system."""
    return {
        "pim": {
            "groups": ["sudo", "adm", "dialout", "gpio", "i2c", "spi"],
            "shell": "/bin/bash",
        },
    }


@pytest.fixture
def expected_network_interfaces():
    """Network interfaces that should be configured."""
    return {
        "eth0": {"type": "dhcp"},
        "eth1": {"type": "static", "address": "172.16.0.1/24"},
    }

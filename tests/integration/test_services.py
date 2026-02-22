"""
Integration tests for Pimeleon services.

These tests require a running VM and verify that services
are properly started and functioning.
"""

import pytest


@pytest.mark.integration
class TestVMBoot:
    """Tests for VM boot success."""

    def test_vm_is_reachable(self, vm_host):
        """VM should be reachable via SSH."""
        assert vm_host.run("echo 'hello'").succeeded

    def test_system_booted(self, vm_host):
        """System should have completed boot."""
        result = vm_host.run("systemctl is-system-running")
        # Accept 'running' or 'degraded' (some services may fail in VM)
        assert result.stdout.strip() in ["running", "degraded"]


@pytest.mark.integration
class TestSystemServices:
    """Tests for essential system services."""

    def test_systemd_networkd_running(self, vm_host):
        """systemd-networkd should be running."""
        service = vm_host.service("systemd-networkd")
        assert service.is_running
        assert service.is_enabled

    def test_systemd_resolved_running(self, vm_host):
        """systemd-resolved should be running."""
        service = vm_host.service("systemd-resolved")
        assert service.is_running
        assert service.is_enabled

    def test_ssh_running(self, vm_host):
        """SSH service should be running."""
        # Try both ssh and sshd service names
        ssh = vm_host.service("ssh")
        sshd = vm_host.service("sshd")
        assert ssh.is_running or sshd.is_running

    def test_dnsmasq_running(self, vm_host):
        """dnsmasq should be running."""
        service = vm_host.service("dnsmasq")
        assert service.is_running
        assert service.is_enabled


@pytest.mark.integration
class TestUserAccess:
    """Tests for user configuration."""

    def test_pim_user_exists(self, vm_host):
        """pim user should exist."""
        user = vm_host.user("pim")
        assert user.exists

    def test_pim_sudo_access(self, vm_host):
        """pim user should have sudo access."""
        user = vm_host.user("pim")
        assert "sudo" in user.groups

    def test_pim_can_sudo(self, vm_host):
        """pim user should be able to run sudo commands."""
        result = vm_host.run("sudo -n id")
        assert result.succeeded
        assert "root" in result.stdout


@pytest.mark.integration
class TestPackages:
    """Tests for installed packages."""

    def test_essential_packages(self, vm_host):
        """Essential packages should be installed."""
        essential = [
            "systemd",
            "dnsmasq",
            "iptables",
        ]
        for pkg_name in essential:
            pkg = vm_host.package(pkg_name)
            assert pkg.is_installed, f"Package {pkg_name} not installed"

    def test_ssh_package(self, vm_host):
        """SSH server should be installed."""
        # Different distros use different package names
        openssh = vm_host.package("openssh-server")
        ssh = vm_host.package("ssh")
        assert openssh.is_installed or ssh.is_installed


@pytest.mark.integration
class TestFilesystem:
    """Tests for filesystem state."""

    def test_root_filesystem_rw(self, vm_host):
        """Root filesystem should be mounted read-write."""
        result = vm_host.run("mount | grep 'on / '")
        assert "rw" in result.stdout

    def test_boot_partition_mounted(self, vm_host):
        """Boot partition should be mounted."""
        mount = vm_host.mount_point("/boot")
        assert mount.exists

    def test_tmp_is_tmpfs(self, vm_host):
        """tmp should be tmpfs for SD card longevity."""
        result = vm_host.run("mount | grep 'on /tmp '")
        # Accept either tmpfs or no separate mount (using root)
        if result.succeeded:
            assert "tmpfs" in result.stdout

    def test_disk_space_available(self, vm_host):
        """Root filesystem should have free space."""
        result = vm_host.run("df -h / | tail -1 | awk '{print $5}'")
        usage = result.stdout.strip().rstrip('%')
        assert int(usage) < 90, f"Disk usage too high: {usage}%"

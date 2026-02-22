"""
Tests for Pimeleon configuration file validation.

Validates that configuration files are present and contain
expected settings.
"""

import re

import pytest


@pytest.mark.unit
class TestNetworkConfig:
    """Tests for systemd-networkd configuration."""

    def test_networkd_configs_exist(self, mounted_root):
        """Network configuration files should exist."""
        network_dir = mounted_root / "etc" / "systemd" / "network"
        network_files = list(network_dir.glob("*.network"))
        assert len(network_files) > 0, "No network config files found"

    def test_wan_interface_config(self, mounted_root):
        """WAN interface should be configured for DHCP."""
        network_dir = mounted_root / "etc" / "systemd" / "network"
        network_files = list(network_dir.glob("*.network"))

        dhcp_found = False
        for nf in network_files:
            content = nf.read_text()
            if "DHCP=yes" in content or "DHCP=ipv4" in content:
                dhcp_found = True
                break

        assert dhcp_found, "No DHCP configuration found for WAN"

    def test_lan_interface_config(self, mounted_root):
        """LAN/management interface should have static IP."""
        network_dir = mounted_root / "etc" / "systemd" / "network"
        network_files = list(network_dir.glob("*.network"))

        static_found = False
        for nf in network_files:
            content = nf.read_text()
            if "Address=" in content:
                static_found = True
                break

        assert static_found, "No static IP configuration found"


@pytest.mark.unit
class TestSSHConfig:
    """Tests for SSH hardening configuration."""

    def test_sshd_config_exists(self, mounted_root):
        """sshd_config should exist."""
        sshd_config = mounted_root / "etc" / "ssh" / "sshd_config"
        assert sshd_config.exists(), "sshd_config not found"

    def test_root_login_disabled(self, mounted_root):
        """Root login should be disabled."""
        sshd_config = mounted_root / "etc" / "ssh" / "sshd_config"

        # Also check sshd_config.d directory
        config_d = mounted_root / "etc" / "ssh" / "sshd_config.d"

        root_login_disabled = False

        # Check main config
        if sshd_config.exists():
            content = sshd_config.read_text()
            if re.search(r"^\s*PermitRootLogin\s+no", content, re.MULTILINE):
                root_login_disabled = True

        # Check config.d files
        if config_d.exists():
            for conf_file in config_d.glob("*.conf"):
                content = conf_file.read_text()
                if re.search(r"^\s*PermitRootLogin\s+no", content, re.MULTILINE):
                    root_login_disabled = True
                    break

        assert root_login_disabled, "Root login should be disabled"

    def test_password_auth_setting(self, mounted_root):
        """Password authentication setting should be explicit."""
        sshd_config = mounted_root / "etc" / "ssh" / "sshd_config"
        config_d = mounted_root / "etc" / "ssh" / "sshd_config.d"

        password_auth_set = False

        if sshd_config.exists():
            content = sshd_config.read_text()
            if re.search(r"^\s*PasswordAuthentication\s+", content, re.MULTILINE):
                password_auth_set = True

        if config_d.exists():
            for conf_file in config_d.glob("*.conf"):
                content = conf_file.read_text()
                if re.search(r"^\s*PasswordAuthentication\s+", content, re.MULTILINE):
                    password_auth_set = True
                    break

        assert password_auth_set, "PasswordAuthentication should be explicitly set"


@pytest.mark.unit
class TestDnsmasqConfig:
    """Tests for dnsmasq DHCP/DNS configuration."""

    def test_dnsmasq_config_exists(self, mounted_root):
        """dnsmasq configuration should exist."""
        dnsmasq_conf = mounted_root / "etc" / "dnsmasq.conf"
        dnsmasq_d = mounted_root / "etc" / "dnsmasq.d"

        assert dnsmasq_conf.exists() or dnsmasq_d.exists(), \
            "dnsmasq configuration not found"

    def test_dhcp_range_configured(self, mounted_root):
        """DHCP range should be configured."""
        dnsmasq_conf = mounted_root / "etc" / "dnsmasq.conf"
        dnsmasq_d = mounted_root / "etc" / "dnsmasq.d"

        dhcp_range_found = False

        if dnsmasq_conf.exists():
            content = dnsmasq_conf.read_text()
            if "dhcp-range=" in content:
                dhcp_range_found = True

        if dnsmasq_d.exists():
            for conf_file in dnsmasq_d.glob("*.conf"):
                content = conf_file.read_text()
                if "dhcp-range=" in content:
                    dhcp_range_found = True
                    break

        assert dhcp_range_found, "DHCP range not configured in dnsmasq"


@pytest.mark.unit
class TestServicesEnabled:
    """Tests for systemd service enablement."""

    def test_networkd_enabled(self, mounted_root):
        """systemd-networkd should be enabled."""
        link = mounted_root / "etc" / "systemd" / "system" / \
            "multi-user.target.wants" / "systemd-networkd.service"
        # Also check if it's a wants link elsewhere
        dbus_link = mounted_root / "etc" / "systemd" / "system" / \
            "dbus-org.freedesktop.network1.service"

        assert link.exists() or dbus_link.exists(), \
            "systemd-networkd not enabled"

    def test_resolved_enabled(self, mounted_root):
        """systemd-resolved should be enabled."""
        link = mounted_root / "etc" / "systemd" / "system" / \
            "multi-user.target.wants" / "systemd-resolved.service"
        dbus_link = mounted_root / "etc" / "systemd" / "system" / \
            "dbus-org.freedesktop.resolve1.service"

        assert link.exists() or dbus_link.exists(), \
            "systemd-resolved not enabled"

    def test_ssh_enabled(self, mounted_root):
        """SSH service should be enabled."""
        # Check various possible locations
        possible_links = [
            mounted_root / "etc" / "systemd" / "system" /
            "multi-user.target.wants" / "ssh.service",
            mounted_root / "etc" / "systemd" / "system" /
            "multi-user.target.wants" / "sshd.service",
            mounted_root / "etc" / "systemd" / "system" /
            "sshd.service",
        ]

        ssh_enabled = any(link.exists() for link in possible_links)
        assert ssh_enabled, "SSH service not enabled"

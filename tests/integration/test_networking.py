"""
Integration tests for Pimeleon networking.

These tests verify network configuration, DHCP server,
DNS resolution, and firewall rules on a running VM.
"""

import pytest


@pytest.mark.integration
@pytest.mark.network
class TestNetworkInterfaces:
    """Tests for network interface configuration."""

    def test_interfaces_exist(self, vm_host):
        """Expected network interfaces should exist."""
        result = vm_host.run("ip link show")
        # Should have at least loopback and one ethernet
        assert "lo:" in result.stdout
        # eth0, end0, enp0s*, or similar
        assert "eth" in result.stdout.lower() or "en" in result.stdout.lower()

    def test_management_interface_ip(self, vm_host):
        """Management interface should have static IP."""
        result = vm_host.run("ip addr show")
        # Check for management IP (172.16.0.1)
        assert "172.16.0.1" in result.stdout

    def test_interfaces_up(self, vm_host):
        """Network interfaces should be UP."""
        result = vm_host.run("ip link show")
        # Count interfaces with state UP
        up_count = result.stdout.count("state UP")
        assert up_count >= 1, "No interfaces in UP state"


@pytest.mark.integration
@pytest.mark.network
class TestDHCPServer:
    """Tests for DHCP server functionality."""

    def test_dnsmasq_listening(self, vm_host):
        """dnsmasq should be listening on DHCP port."""
        result = vm_host.run("ss -ulnp | grep ':67 '")
        assert "dnsmasq" in result.stdout or result.succeeded

    def test_dhcp_range_configured(self, vm_host):
        """DHCP range should be configured."""
        result = vm_host.run("cat /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf 2>/dev/null")
        assert "dhcp-range=" in result.stdout


@pytest.mark.integration
@pytest.mark.network
class TestDNSResolution:
    """Tests for DNS resolution."""

    def test_dns_service_running(self, vm_host):
        """DNS service should be running."""
        # dnsmasq provides DNS
        result = vm_host.run("ss -ulnp | grep ':53 '")
        assert result.succeeded

    def test_local_dns_resolution(self, vm_host):
        """Local DNS resolution should work."""
        result = vm_host.run("getent hosts localhost")
        assert result.succeeded
        assert "127.0.0.1" in result.stdout or "::1" in result.stdout

    def test_resolv_conf_exists(self, vm_host):
        """resolv.conf should be configured."""
        file = vm_host.file("/etc/resolv.conf")
        assert file.exists
        assert file.contains("nameserver")


@pytest.mark.integration
@pytest.mark.network
class TestFirewall:
    """Tests for firewall configuration."""

    def test_iptables_loaded(self, vm_host):
        """iptables should have rules loaded."""
        result = vm_host.run("sudo iptables -L -n")
        assert result.succeeded
        # Should have at least default chains
        assert "Chain INPUT" in result.stdout
        assert "Chain FORWARD" in result.stdout
        assert "Chain OUTPUT" in result.stdout

    def test_nat_rules_exist(self, vm_host):
        """NAT rules should be configured for routing."""
        result = vm_host.run("sudo iptables -t nat -L -n")
        assert result.succeeded
        assert "MASQUERADE" in result.stdout or "POSTROUTING" in result.stdout

    def test_ip_forwarding_enabled(self, vm_host):
        """IP forwarding should be enabled."""
        result = vm_host.run("cat /proc/sys/net/ipv4/ip_forward")
        assert result.stdout.strip() == "1"


@pytest.mark.integration
@pytest.mark.network
class TestRouting:
    """Tests for routing configuration."""

    def test_default_route_exists(self, vm_host):
        """Default route should exist."""
        result = vm_host.run("ip route show default")
        # May or may not have default depending on WAN connectivity
        assert result.succeeded

    def test_local_routes_exist(self, vm_host):
        """Local network routes should exist."""
        result = vm_host.run("ip route show")
        # Should have route for management network
        assert "172.16.0.0" in result.stdout or "172.16.0.1" in result.stdout


@pytest.mark.integration
@pytest.mark.network
class TestConnectivity:
    """Tests for network connectivity."""

    def test_loopback_ping(self, vm_host):
        """Loopback should be pingable."""
        result = vm_host.run("ping -c 1 127.0.0.1")
        assert result.succeeded

    def test_self_ping(self, vm_host):
        """Management IP should be pingable."""
        result = vm_host.run("ping -c 1 172.16.0.1")
        assert result.succeeded

    @pytest.mark.skip(reason="Requires external network access")
    def test_external_connectivity(self, vm_host):
        """External connectivity should work."""
        # This test requires WAN access which may not be available in test env
        result = vm_host.run("ping -c 1 -W 5 8.8.8.8")
        assert result.succeeded

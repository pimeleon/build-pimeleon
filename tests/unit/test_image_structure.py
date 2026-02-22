"""
Tests for Pimeleon image structure validation.

These tests mount the image and verify filesystem structure
without booting a VM.
"""

import pytest


@pytest.mark.unit
class TestBootPartition:
    """Tests for the boot partition (FAT32)."""

    def test_boot_partition_exists(self, mounted_boot):
        """Boot partition should mount successfully."""
        assert mounted_boot.exists()
        assert mounted_boot.is_dir()

    def test_kernel_image_exists(self, mounted_boot):
        """Kernel image should be present."""
        # RPi 3B+ uses kernel7.img, RPi 4 uses kernel8.img
        kernel_files = list(mounted_boot.glob("kernel*.img"))
        assert len(kernel_files) > 0, "No kernel image found"

    def test_config_txt_exists(self, mounted_boot):
        """config.txt should be present."""
        config_file = mounted_boot / "config.txt"
        assert config_file.exists(), "config.txt not found"

    def test_cmdline_txt_exists(self, mounted_boot):
        """cmdline.txt should be present."""
        cmdline_file = mounted_boot / "cmdline.txt"
        assert cmdline_file.exists(), "cmdline.txt not found"

    def test_device_tree_files(self, mounted_boot):
        """Device tree files should be present."""
        dtb_files = list(mounted_boot.glob("*.dtb"))
        assert len(dtb_files) > 0, "No device tree files found"

    def test_overlays_directory(self, mounted_boot):
        """Overlays directory should exist."""
        overlays_dir = mounted_boot / "overlays"
        assert overlays_dir.exists(), "overlays directory not found"
        assert overlays_dir.is_dir()


@pytest.mark.unit
class TestRootPartition:
    """Tests for the root partition (ext4)."""

    def test_root_partition_exists(self, mounted_root):
        """Root partition should mount successfully."""
        assert mounted_root.exists()
        assert mounted_root.is_dir()

    def test_essential_directories(self, mounted_root):
        """Essential Linux directories should exist."""
        essential_dirs = ["bin", "etc", "home", "lib", "opt", "root", "usr", "var"]
        for dir_name in essential_dirs:
            dir_path = mounted_root / dir_name
            assert dir_path.exists(), f"Missing directory: {dir_name}"

    def test_systemd_directory(self, mounted_root):
        """systemd configuration should exist."""
        systemd_dir = mounted_root / "etc" / "systemd"
        assert systemd_dir.exists(), "systemd directory not found"

    def test_network_config_directory(self, mounted_root):
        """systemd-networkd configuration should exist."""
        network_dir = mounted_root / "etc" / "systemd" / "network"
        assert network_dir.exists(), "systemd network directory not found"

    def test_ssh_directory(self, mounted_root):
        """SSH configuration directory should exist."""
        ssh_dir = mounted_root / "etc" / "ssh"
        assert ssh_dir.exists(), "SSH configuration not found"


@pytest.mark.unit
class TestFstab:
    """Tests for /etc/fstab configuration."""

    def test_fstab_exists(self, mounted_root):
        """fstab should exist."""
        fstab = mounted_root / "etc" / "fstab"
        assert fstab.exists(), "fstab not found"

    def test_fstab_has_root_mount(self, mounted_root):
        """fstab should have root mount entry."""
        fstab = mounted_root / "etc" / "fstab"
        content = fstab.read_text()
        # Check for root partition mount (PARTUUID or /dev/...)
        assert "/" in content, "Root mount not found in fstab"

    def test_fstab_has_boot_mount(self, mounted_root):
        """fstab should have boot mount entry."""
        fstab = mounted_root / "etc" / "fstab"
        content = fstab.read_text()
        assert "/boot" in content, "Boot mount not found in fstab"


@pytest.mark.unit
class TestUsers:
    """Tests for user configuration."""

    def test_passwd_exists(self, mounted_root):
        """passwd file should exist."""
        passwd = mounted_root / "etc" / "passwd"
        assert passwd.exists(), "passwd not found"

    def test_pim_user_exists(self, mounted_root):
        """pim user should exist."""
        passwd = mounted_root / "etc" / "passwd"
        content = passwd.read_text()
        assert "pim:" in content, "pim user not found"

    def test_pim_home_directory(self, mounted_root):
        """pim home directory should exist."""
        pim_home = mounted_root / "home" / "pim"
        assert pim_home.exists(), "pim home directory not found"

    def test_shadow_permissions(self, mounted_root):
        """shadow file should have restricted permissions."""
        shadow = mounted_root / "etc" / "shadow"
        if shadow.exists():
            mode = shadow.stat().st_mode & 0o777
            assert mode <= 0o640, f"shadow has insecure permissions: {oct(mode)}"

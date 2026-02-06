# Ansible Playbooks

Documentation for Ansible playbooks, group variables, and configuration management.

## Directory Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── .ansible-lint            # Linting rules
├── inventory/
│   └── group_vars/          # Platform-specific variables
│       ├── all/             # Global defaults
│       │   ├── main.yml     # System settings
│       │   ├── network.yml  # Network configuration
│       │   └── services.yml # Service management
│       ├── raspberrypi/     # Pi family defaults
│       │   └── main.yml
│       ├── raspberrypi_3bplus/  # Pi 3B+ specific
│       │   └── main.yml
│       └── raspberrypi_4b/      # Pi 4B specific
│           └── main.yml
└── playbooks/
    ├── main.yml             # Entry point
    └── tasks/
        ├── base-setup.yml       # Base system config
        ├── network-setup.yml    # Network services
        └── security-hardening.yml  # Security config
```

## Group Variable Inheritance

Variables are loaded in order (later overrides earlier):

```
all/main.yml          # Loaded first (defaults)
    ↓
raspberrypi/main.yml  # Pi family settings
    ↓
raspberrypi_3bplus/main.yml  # Platform-specific
```

**Example:** If `ram_mb: 1024` in `all/` and `ram_mb: 4096` in `raspberrypi_4b/`, the Pi 4B build uses `4096`.

## Key Variables

### System Configuration (`all/main.yml`)

| Variable | Default | Description |
|----------|---------|-------------|
| `system_hostname` | `pimeleon` | System hostname |
| `pimeleon_user` | `pi` | Default user account |
| `debian_version` | `bullseye` | Debian codename |
| `platform_model` | `3B+` | Pi model identifier |

### Network Configuration (`all/network.yml`)

| Variable | Default | Description |
|----------|---------|-------------|
| `wan_interface` | `eth0` | WAN interface name |
| `lan_ip` | `192.168.42.1` | LAN IP address |
| `dhcp_range_start` | `192.168.42.100` | DHCP pool start |
| `dhcp_range_end` | `192.168.42.200` | DHCP pool end |
| `wifi_ssid` | `pimeleon` | WiFi AP SSID |
| `wifi_channel` | `6` | WiFi channel |

### Platform-Specific (`raspberrypi_*/main.yml`)

| Variable | Pi 3B+ | Pi 4B | Description |
|----------|--------|-------|-------------|
| `architecture` | `armhf` | `arm64` | CPU architecture |
| `ram_mb` | `1024` | `4096` | RAM in MB |
| `device_tree` | `bcm2710-rpi-3-b-plus.dtb` | `bcm2711-rpi-4-b.dtb` | Device tree blob |
| `ethernet_max_speed_mbps` | `300` | `1000` | Max ethernet speed |
| `hostapd_max_sta` | `10` | `20` | Max WiFi clients |

## Playbooks

### Main Playbook (`main.yml`)

Entry point that imports all task files:

```yaml
- name: Pimeleon Complete Setup
  hosts: pimeleon
  become: true
  tasks:
    - import_tasks: tasks/base-setup.yml
    - import_tasks: tasks/network-setup.yml
    - import_tasks: tasks/security-hardening.yml
```

### Base Setup (`tasks/base-setup.yml`)

- System hostname configuration
- Essential package installation
- Hardware group creation (gpio, i2c, spi)
- Service enable/disable
- Directory structure creation

### Network Setup (`tasks/network-setup.yml`)

- systemd-networkd configuration
- dnsmasq DHCP/DNS setup
- hostapd WiFi AP configuration
- nftables firewall rules

### Security Hardening (`tasks/security-hardening.yml`)

- SSH hardening
- fail2ban configuration
- Automatic security updates
- Audit logging

## Execution Flow

During image build (`stage2-customize.sh`):

1. **Inventory Generation**

   ```ini
   [all]
   pimeleon ansible_connection=chroot ansible_host=/tmp/build/mount

   [raspberrypi]
   pimeleon

   [raspberrypi_3bplus]  # or raspberrypi_4b based on PIMELEON_RPI_MODEL
   pimeleon
   ```

2. **Group Vars Copied** to work directory

3. **Extra Vars Passed**

   ```bash
   --extra-vars "platform_model=3B+"
   --extra-vars "debian_version=bullseye"
   --extra-vars "pimeleon_initial_password=netblox"
   ```

4. **Playbooks Execute** via chroot connection (no SSH needed)

## Adding New Platforms

1. Create `ansible/inventory/group_vars/raspberrypi_newmodel/main.yml`
2. Define platform-specific variables
3. Update `stage2-customize.sh` platform group mapping if needed

## Conditional Tasks

Use platform variables for conditional execution:

```yaml
# Only on Pi 4B
- name: Enable USB 3.0 features
  when: platform_model == "4B"

# Only if WiFi available
- name: Configure hostapd
  when: hardware_features.wifi | default(false)

# Resource-aware
- name: Install heavy security tools
  when: ram_mb | int >= 1024
```

## Version-Specific Configuration

Access version-specific settings:

```yaml
- name: Check if nftables is default
  debug:
    msg: "nftables default: {{ version_specific[debian_version].nftables_default }}"
```

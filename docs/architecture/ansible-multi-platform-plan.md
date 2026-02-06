# Ansible Multi-Platform Optimization Plan

This document outlines the plan to optimize Ansible configuration for supporting multiple
Raspberry Pi platforms with different configuration values and service subsets.

## Current Issues

### 1. Undefined Variables

The `network-setup.yml` task file references variables that are **never defined**:

| Variable | Used In | Current State |
|----------|---------|---------------|
| `wan_interface` | network-setup.yml | Undefined (will fail) |
| `lan_interface` | network-setup.yml | Undefined (will fail) |
| `lan_ip` | network-setup.yml | Undefined (will fail) |
| `dhcp_range_start` | network-setup.yml | Undefined (will fail) |
| `dhcp_range_end` | network-setup.yml | Undefined (will fail) |

### 2. No Platform-Specific Configs

All configuration values are hardcoded in task files with no distinction between platforms.

### 3. No Variable Passing

Platform variables (`PIMELEON_RPI_MODEL`) are not passed from build scripts to Ansible.

### 4. Missing Directory Structure

No `group_vars/` or `host_vars/` directories exist for organizing platform-specific variables.

---

## Phase 1: Fix Immediate Issues (High Priority)

### 1.1 Create group_vars Directory Structure

```
ansible/inventory/group_vars/
├── all/
│   ├── main.yml      # Global defaults (hostname, user)
│   ├── network.yml   # Network defaults (interfaces, DHCP ranges)
│   └── services.yml  # Service enable/disable lists
├── raspberrypi/
│   └── main.yml      # Pi-family defaults (kernel, firmware)
└── raspberrypi_3bplus/
    └── main.yml      # Pi 3B+ specific (device tree, CPU freq)
```

### 1.2 Create `all/main.yml` (Global Defaults)

```yaml
---
# Global defaults for all platforms

# Platform identification (overridden per platform)
platform_family: "raspberrypi"
platform_model: "3B+"

# System settings
system_hostname: "pimeleon"
system_timezone: "Etc/UTC"
system_locale: "en_US.UTF-8"

# User configuration
pimeleon_user: "pi"
pimeleon_initial_password: "{{ lookup('env', 'PIMELEON_INITIAL_PASSWORD') | default('changeme', true) }}"

# Hardware feature flags (defaults - override per platform)
hardware_features:
  uart: true
  spi: true
  i2c: true
  gpio: true
  wifi: true
  bluetooth: true

# Hardware groups to create
hardware_groups:
  - gpio
  - i2c
  - spi
  - video
  - audio
  - input
```

### 1.3 Create `all/network.yml` (Network Defaults)

```yaml
---
# Network configuration defaults

# Interface naming
wan_interface: "eth0"
lan_interface: "eth1"
wifi_interface: "wlan0"
mgmt_interface: "eth0:0"

# LAN network settings
lan_ip: "192.168.42.1"
lan_netmask: "255.255.255.0"
lan_network: "192.168.42.0/24"

# WiFi AP network settings
wifi_ap_ip: "192.168.42.1"
wifi_ap_netmask: "255.255.255.0"
wifi_ap_network: "192.168.42.0/24"

# Management network
mgmt_ip: "172.16.0.1"
mgmt_netmask: "255.255.255.0"

# DHCP configuration
dhcp_range_start: "192.168.42.100"
dhcp_range_end: "192.168.42.200"
dhcp_lease_time: "12h"

wifi_dhcp_range_start: "192.168.42.100"
wifi_dhcp_range_end: "192.168.42.200"

# WiFi AP configuration
wifi_ssid: "pimeleon"
wifi_passphrase: "changeme123"
wifi_channel: 6
wifi_hw_mode: "g"      # g=2.4GHz, a=5GHz
wifi_country_code: "US"

# DNS servers
upstream_dns:
  - "8.8.8.8"
  - "8.8.4.4"
```

### 1.4 Create `all/services.yml` (Service Configuration)

```yaml
---
# Service configuration defaults

# Services to enable
enabled_services:
  essential:
    - ssh
    - systemd-networkd
    - systemd-resolved
    - rsyslog
  network:
    - isc-dhcp-server
    - nftables
  optional:
    - hostapd

# Services to disable
disabled_services:
  - dhcpcd
  - networking
  - wpa_supplicant
  - bluetooth
  - avahi-daemon

# Service package mapping
service_packages:
  dhcp: "isc-dhcp-server"
  dns: "dnsmasq"
  wifi_ap: "hostapd"
  firewall: "nftables"
```

### 1.5 Update stage2-customize.sh

Update the Ansible invocation in `containers/builder/scripts/stage2-customize.sh` (lines 169-184):

```bash
# Apply Ansible playbooks if available
if [[ -d "${ANSIBLE_DIR}/playbooks" ]] && [[ -n "$(ls -A ${ANSIBLE_DIR}/playbooks/*.yml 2>/dev/null)" ]]; then
    log_info "Applying Ansible playbooks"
    export ANSIBLE_HOST_KEY_CHECKING=False

    # Determine platform group from environment
    PLATFORM_GROUP="raspberrypi_$(echo ${PIMELEON_RPI_MODEL} | tr '[:upper:]' '[:lower:]' | tr -d '+' | tr ' ' '')"

    # Create temporary inventory with group assignments
    cat > "${WORK_DIR}/inventory" <<EOF
[all]
pimeleon ansible_connection=chroot ansible_host=${MOUNT_POINT}

[raspberrypi]
pimeleon

[${PLATFORM_GROUP}]
pimeleon

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOF

    # Export environment variables for Ansible to pick up
    export PIMELEON_RPI_MODEL="${PIMELEON_RPI_MODEL}"
    export PIMELEON_IMAGE_SIZE="${PIMELEON_IMAGE_SIZE}"
    export PIMELEON_INITIAL_PASSWORD="${PIMELEON_INITIAL_PASSWORD:-netblox}"

    # Run playbooks with extra vars for environment override
    for playbook in ${ANSIBLE_DIR}/playbooks/*.yml; do
        log_info "Running playbook: $(basename $playbook)"
        ansible-playbook \
            -i "${WORK_DIR}/inventory" \
            --extra-vars "platform_model=${PIMELEON_RPI_MODEL}" \
            --extra-vars "pimeleon_initial_password=${PIMELEON_INITIAL_PASSWORD}" \
            "$playbook" || log_warn "Playbook failed: $playbook"
    done
fi
```

---

## Phase 2: Platform-Specific Configuration

### 2.1 Create `raspberrypi/main.yml` (Pi Family Defaults)

```yaml
---
# Raspberry Pi family defaults

platform_family: "raspberrypi"
bootloader_type: "pi-firmware"

# Kernel and firmware
kernel_package: "raspberrypi-kernel"
firmware_packages:
  - libraspberrypi-bin
  - libraspberrypi0
  - firmware-brcm80211
  - pi-bluetooth

# Boot partition
boot_partition_size: "256M"
boot_partition_fs: "vfat"

# Pi-specific hardware features
hardware_features:
  uart: true
  spi: true
  i2c: true
  gpio: true
  camera: true
  audio: true
  wifi: true
  bluetooth: true

# config.txt template path
config_txt_template: "templates/raspberrypi/config.txt.j2"
```

### 2.2 Create `raspberrypi_3bplus/main.yml` (Pi 3B+ Specific)

```yaml
---
# Raspberry Pi 3 Model B+ specific configuration

platform_model: "3B+"
display_name: "Raspberry Pi 3 Model B+"

# Hardware specs
architecture: "armhf"
soc: "BCM2710"
cpu_cores: 4
cpu_freq_default: 1200
cpu_freq_max: 1400
ram_mb: 1024

# Device tree
device_tree: "bcm2710-rpi-3-b-plus.dtb"
device_tree_overlays:
  - "pi3-disable-bt.dtbo"

# Network performance (USB 2.0 limited)
ethernet_available: true
ethernet_max_speed_mbps: 300  # Limited by USB 2.0
wifi_max_speed_mbps: 100

# config.txt parameters
config_txt:
  enable_uart: 1
  dtparam_spi: "on"
  dtparam_i2c: "on"
  gpu_mem: 16
  arm_freq: 1200
  over_voltage: 2
  max_usb_current: 1

# hostapd WiFi capabilities (Pi 3B+)
hostapd_ht_capab: ""
hostapd_max_sta: 10
```

### 2.3 Create `raspberrypi_4b/main.yml` (Pi 4B Specific)

```yaml
---
# Raspberry Pi 4 Model B specific configuration

platform_model: "4B"
display_name: "Raspberry Pi 4 Model B"

# Hardware specs
architecture: "arm64"  # 64-bit capable
soc: "BCM2711"
cpu_cores: 4
cpu_freq_default: 1500
cpu_freq_max: 1800
ram_mb: "{{ lookup('env', 'PIMELEON_RAM_SIZE') | default(4096, true) }}"

# Device tree
device_tree: "bcm2711-rpi-4-b.dtb"
device_tree_overlays:
  - "vc4-kms-v3d"

# Network performance (true Gigabit)
ethernet_available: true
ethernet_max_speed_mbps: 1000
wifi_max_speed_mbps: 150

# config.txt parameters
config_txt:
  enable_uart: 1
  dtparam_spi: "on"
  dtparam_i2c: "on"
  gpu_mem: 256         # More RAM available
  arm_freq: 1800
  over_voltage: 4
  max_usb_current: 1

# USB 3.0 support
usb3_enabled: true

# hostapd WiFi capabilities (Pi 4B - improved)
hostapd_ht_capab: "[HT40+][HT40-][SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40]"
hostapd_vht_enabled: true
hostapd_max_sta: 20
```

### 2.4 Create `raspberrypi_zerow/main.yml` (Zero W Specific)

```yaml
---
# Raspberry Pi Zero W specific configuration

platform_model: "Zero W"
display_name: "Raspberry Pi Zero W"

# Hardware specs
architecture: "armhf"
soc: "BCM2835"
cpu_cores: 1
cpu_freq_default: 1000
cpu_freq_max: 1000
ram_mb: 512

# Device tree
device_tree: "bcm2708-rpi-zero-w.dtb"

# No Ethernet - WiFi only
ethernet_available: false
wifi_max_speed_mbps: 50

# Reduced service set (limited resources)
enabled_services:
  essential:
    - ssh
    - systemd-networkd
    - systemd-resolved
  network:
    - hostapd
    - nftables
  optional: []

# Disable resource-intensive services
disabled_services:
  - isc-dhcp-server  # Use dnsmasq instead
  - fail2ban        # Too heavy
  - auditd          # Too heavy

# config.txt parameters (conservative)
config_txt:
  enable_uart: 1
  dtparam_spi: "off"   # Disabled by default
  dtparam_i2c: "off"
  gpu_mem: 16
  arm_freq: 1000

# Minimal hostapd config
hostapd_ht_capab: ""
hostapd_max_sta: 5  # Limited by resources
```

---

## Phase 3: Conditional Task Patterns

### 3.1 Platform-Based Conditionals (base-setup.yml)

```yaml
---
# Base setup tasks with platform conditionals

- name: Set system hostname
  ansible.builtin.hostname:
    name: "{{ system_hostname }}"

- name: Install kernel package
  ansible.builtin.apt:
    name: "{{ kernel_package }}"
    state: present
  when: kernel_package is defined

- name: Install firmware packages
  ansible.builtin.apt:
    name: "{{ firmware_packages }}"
    state: present
  when:
    - firmware_packages is defined
    - firmware_packages | length > 0

# Pi 4B specific: 64-bit kernel option
- name: Install 64-bit kernel for Pi 4B
  ansible.builtin.apt:
    name: raspberrypi-kernel-arm64
    state: present
  when:
    - platform_model == "4B"
    - architecture == "arm64"

# Zero W specific: Use lightweight DHCP
- name: Install dnsmasq for Zero W (lighter than isc-dhcp-server)
  ansible.builtin.apt:
    name: dnsmasq
    state: present
  when: platform_model == "Zero W"
```

### 3.2 Feature-Based Conditionals (network-setup.yml)

```yaml
---
# Network setup with feature conditionals

- name: Configure WAN interface
  ansible.builtin.copy:
    dest: /etc/systemd/network/10-wan.network
    content: |
      [Match]
      Name={{ wan_interface }}

      [Network]
      DHCP=yes
      IPForward=yes
    mode: '0644'
  when: ethernet_available | default(true)

- name: Configure WiFi interface for AP mode
  ansible.builtin.copy:
    dest: /etc/systemd/network/20-wlan.network
    content: |
      [Match]
      Name={{ wifi_interface }}

      [Network]
      Address={{ wifi_ap_ip }}/24
      IPForward=yes
    mode: '0644'
  when: hardware_features.wifi | default(false)

- name: Configure hostapd
  ansible.builtin.template:
    src: templates/hostapd.conf.j2
    dest: /etc/hostapd/hostapd.conf
    mode: '0600'
  when:
    - hardware_features.wifi | default(false)
    - "'hostapd' in enabled_services.network | default([])"

- name: Enable hostapd service
  ansible.builtin.systemd:
    name: hostapd
    enabled: true
  when:
    - hardware_features.wifi | default(false)
    - "'hostapd' in enabled_services.network | default([])"
  failed_when: false
```

### 3.3 Service Management with Platform Awareness

```yaml
---
# Service management with platform conditionals

- name: Enable essential services
  ansible.builtin.systemd:
    name: "{{ item }}"
    enabled: true
    state: started
  loop: "{{ enabled_services.essential }}"
  failed_when: false

- name: Enable network services (full platforms)
  ansible.builtin.systemd:
    name: "{{ item }}"
    enabled: true
  loop: "{{ enabled_services.network }}"
  when:
    - ram_mb | int >= 512
    - item not in disabled_services | default([])
  failed_when: false

# Resource-conscious service selection for Zero W
- name: Skip heavy services on resource-limited platforms
  ansible.builtin.debug:
    msg: "Skipping {{ item }} on {{ display_name }} (limited resources)"
  loop:
    - fail2ban
    - auditd
    - rkhunter
  when: ram_mb | int < 1024
```

---

## Implementation Summary

### Files to Create

| File | Description |
|------|-------------|
| `ansible/inventory/group_vars/all/main.yml` | Global defaults |
| `ansible/inventory/group_vars/all/network.yml` | Network defaults |
| `ansible/inventory/group_vars/all/services.yml` | Service configuration |
| `ansible/inventory/group_vars/raspberrypi/main.yml` | Pi family defaults |
| `ansible/inventory/group_vars/raspberrypi_3bplus/main.yml` | Pi 3B+ specific |
| `ansible/inventory/group_vars/raspberrypi_4b/main.yml` | Pi 4B specific |
| `ansible/inventory/group_vars/raspberrypi_zerow/main.yml` | Zero W specific |

### Files to Modify

| File | Changes |
|------|---------|
| `containers/builder/scripts/stage2-customize.sh` | Update inventory generation and variable passing |
| `ansible/playbooks/tasks/base-setup.yml` | Add platform conditionals |
| `ansible/playbooks/tasks/network-setup.yml` | Add feature conditionals |
| `ansible/playbooks/tasks/security-hardening.yml` | Add resource-aware conditionals |

---

## Platform Differences Summary

| Configuration | Pi 3B+ | Pi 4B | Zero W |
|---------------|--------|-------|--------|
| Architecture | armhf (32-bit) | arm64 (64-bit) | armhf |
| CPU Frequency | 1200-1400 MHz | 1500-1800 MHz | 1000 MHz |
| RAM | 1 GB | 2-8 GB | 512 MB |
| Ethernet | ~300 Mbps (USB 2.0) | ~940 Mbps (native) | None |
| WiFi | Built-in | Built-in | Built-in |
| DHCP Server | isc-dhcp-server | isc-dhcp-server | dnsmasq (lighter) |
| Security Services | Full | Full | Minimal |
| hostapd max_sta | 10 | 20 | 5 |

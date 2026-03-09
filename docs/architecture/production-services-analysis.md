# Production Services Analysis

Analysis of critical services running on the production Pimeleon (gw host).

**Audit Date:** 2025-11-23

## System Overview

| Property | Value |
|----------|-------|
| **Hostname** | gw |
| **OS** | Raspbian GNU/Linux 10 (Buster) |
| **Kernel** | 6.12.41-v7+ |
| **Hardware** | Raspberry Pi 3B+ |
| **RAM** | 921MB |
| **Storage** | 15GB (47% used) |

## Network Architecture

| Interface | IP Address | Role |
|-----------|------------|------|
| **eth0** | DHCP client | WAN - Internet uplink |
| **wlan0** | 192.168.42.1/24 | WiFi - Wireless access point |

### IPv6 Configuration

- eth1: fd00:ffff:0:1176::1/64 (ULA)
- wlan0: fd00:ffff:0:1177::1/64 (ULA)

## Critical Services

### Tier 1: Core Router Services

| Service | Package | Port | Role |
|---------|---------|------|------|
| systemd-networkd | systemd | - | Interface configuration |
| hostapd | hostapd | - | WiFi Access Point (SSID: keen) |
| isc-dhcp-server | isc-dhcp-server | 67/udp | DHCP for eth1/wlan0 |
| bind9 | bind9 | 53 | Primary DNS server |
| nftables | nftables | - | Firewall + NAT |
| ssh | openssh-server | 24442 | Remote access (non-standard port) |
| fail2ban | fail2ban | - | Brute-force protection |

### Tier 2: DNS Stack (Multi-layer)

```
Clients → BIND9 (53) → Pi-hole (5553) → dnscrypt-proxy (5054) → Internet
```

| Service | Package | Port | Role |
|---------|---------|------|------|
| bind9 | bind9 | 53 | Primary DNS, DDNS integration |
| pihole-FTL | pihole | 5553 | Ad blocking, DNS filtering |
| dnscrypt-proxy | dnscrypt-proxy | 5054 | Encrypted upstream DNS |

### Tier 3: Proxy Services

| Service | Package | Port | Role |
|---------|---------|------|------|
| privoxy | privoxy | 8118 | Privacy proxy, ad blocking |
| squid | squid | 3128/3129 | Caching proxy |
| tor | tor | 9050/4439 | Anonymizing network |

**Note:** HTTP traffic (port 80) is transparently redirected to Privoxy via nftables.

### Tier 4: Web & API Services

| Service | Package | Port | Role |
|---------|---------|------|------|
| nginx | nginx | 80/443/8443 | Web server, reverse proxy |
| pi-router-api | custom | 5000 | REST API (Flask) |
| ddclient | ddclient | - | Dynamic DNS updates |

### Tier 5: File Sharing (Development)

| Service | Package | Port | Role |
|---------|---------|------|------|
| smbd | samba | 139/445 | SMB/CIFS shares |
| nmbd | samba | 137/138 | NetBIOS name service |
| nfs-server | nfs-kernel-server | 2049 | NFS exports |

### Tier 6: Supporting Services

| Service | Package | Port | Role |
|---------|---------|------|------|
| avahi-daemon | avahi-daemon | 5353 | mDNS/DNS-SD |
| postfix | postfix | 25 (localhost) | Local mail transport |
| systemd-resolved | systemd | 5355 | mDNS/LLMNR |

## Custom Services

| Service | Location | Description |
|---------|----------|-------------|
| pi-router-api | /opt/pi-router/api | Flask REST API |
| pi-power-monitor | /opt/pi-router | Power monitoring daemon |

## Firewall Configuration (nftables)

### Default Policies

- **Input:** DROP (whitelist)
- **Forward:** DROP (whitelist)
- **Output:** ACCEPT

### NAT Rules

- Masquerade LAN (eth1) → WAN (eth0)
- Masquerade WiFi (wlan0) → WAN (eth0)
- HTTP redirect to Privoxy (8118)
- Port forwarding: TCP 33996, UDP 50044 → 192.168.42.10

### Allowed Inbound (WAN)

- HTTPS (443)
- GitLab (8443)
- DNS (53)
- Tor (4439)
- ICMP

## DHCP Configuration

| Setting | Value |
|---------|-------|
| Domain | pirouter.dev |
| Wired LAN Pool | 192.168.42.100-254 |
| WiFi Pool | 192.168.42.100-254 |
| DNS Server | 192.168.42.1 |
| Lease Time | 86400s (default) |
| DDNS | Enabled (updates BIND9) |

## WiFi Configuration (hostapd)

| Setting | Value |
|---------|-------|
| SSID | keen |
| Interface | wlan0 |
| Mode | 802.11g |
| Channel | 6 |
| Security | WPA2-PSK (CCMP/TKIP) |
| WMM | Enabled |

## Resource Considerations

### Memory Usage

- Total: 921MB
- Used: ~51%
- Swap: 206MB active (indicates memory pressure)

### Recommendations for Pi 3B+

1. Running Tor + Privoxy + Squid simultaneously is resource-heavy
2. Consider disabling unused services (NFS, Samba if not needed)
3. Squid caching may be excessive for limited RAM

## Build Profile Mapping

| Service | Development | Production |
|---------|-------------|------------|
| systemd-networkd | ✅ | ✅ |
| hostapd | ✅ | ✅ |
| isc-dhcp-server | ✅ | ✅ |
| bind9 | ✅ | ✅ |
| nftables | ✅ | ✅ |
| ssh | ✅ | ✅ |
| fail2ban | ✅ | ✅ |
| pihole-FTL | ✅ | ✅ |
| dnscrypt-proxy | ✅ | ✅ |
| privoxy | ✅ | ✅ |
| nginx | ✅ | ✅ |
| pi-router-api | ✅ | ✅ |
| ddclient | ✅ | ✅ |
| squid | ✅ | ❌ |
| tor | ✅ | ❌ |
| samba | ✅ | ❌ |
| nfs-server | ✅ | ❌ |
| dev-tools | ✅ | ❌ |

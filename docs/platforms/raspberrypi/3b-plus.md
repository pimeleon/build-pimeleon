# Raspberry Pi 3 Model B+ Guide

## Overview

The Raspberry Pi 3B+ is the primary, flagship platform for Pi Router. It offers excellent value and proven reliability for router deployments.

## Specifications

| Feature | Specification |
|---------|---------------|
| CPU | Broadcom BCM2837B0, Quad-core Cortex-A53 @ 1.4GHz |
| Architecture | ARMv7 (32-bit) |
| RAM | 1GB LPDDR2 SDRAM |
| Ethernet | Gigabit Ethernet over USB 2.0 (~300 Mbps max) |
| WiFi | 2.4GHz and 5GHz 802.11ac |
| Bluetooth | Bluetooth 4.2, BLE |
| USB | 4x USB 2.0 |
| GPIO | 40-pin header |
| Power | 5V/2.5A via micro USB |

## Building for Pi 3B+

```bash
# Default build (Pi 3B+ is the default)
export DOCKER_BUILDKIT=1 && docker compose run --rm builder

# Explicit platform specification
export DOCKER_BUILDKIT=1 && \
  PIMELEON_RPI_MODEL=3B+ \
  docker compose run --rm builder
```

## Hardware Profile

```yaml
# platforms/raspberrypi/profiles/3b-plus.yaml
platform: raspberrypi
model: 3B+
architecture: armhf
cpu_family: bcm2837
```

## Network Configuration

The Pi 3B+ uses the built-in Ethernet port as the primary WAN interface. For LAN connectivity, use a USB Ethernet adapter or configure WiFi as an access point.

## Known Limitations

- Ethernet limited to ~300 Mbps due to USB 2.0 bus
- Single onboard Ethernet port requires USB adapter for dual-port router setup

## Resources

- [Raspberry Pi 3B+ Product Page](https://www.raspberrypi.com/products/raspberry-pi-3-model-b-plus/)
- [Pi 3B+ Datasheet](https://datasheets.raspberrypi.com/rpi3/raspberry-pi-3-b-plus-product-brief.pdf)

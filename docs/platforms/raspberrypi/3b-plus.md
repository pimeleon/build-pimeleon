# Raspberry Pi 3 Model B+

The Raspberry Pi 3B+ is the **primary, fully-supported platform** for Pimeleon. All build scripts are optimized and tested for this hardware.

## Status

✅ **Fully Supported** - Primary development platform, production-ready

## Hardware Specifications

| Feature | Specification |
|---------|---------------|
| SoC | Broadcom BCM2710 |
| CPU | Quad-core Cortex-A53 @ 1.4 GHz |
| Architecture | ARMv7 (32-bit, armhf) |
| RAM | 1 GB LPDDR2 |
| Ethernet | Gigabit over USB 2.0 (~300 Mbps actual) |
| WiFi | 802.11ac dual-band (2.4/5 GHz) |
| Bluetooth | 4.2, BLE |
| USB | 4x USB 2.0 |
| GPIO | 40-pin header |
| Power | 5V/2.5A via micro USB |

## Building

The Pi 3B+ is the default platform - no special flags required:

```bash
export DOCKER_BUILDKIT=1 && docker compose run --rm builder
```

Or explicitly:

```bash
export DOCKER_BUILDKIT=1 && \
  PIMELEON_RPI_MODEL=3B+ \
  docker compose run --rm builder
```

## Build Configuration

### Boot Configuration (config.txt)

The build creates this optimized `config.txt`:

```ini
# Pimeleon Boot Configuration
enable_uart=1
dtparam=spi=on
dtparam=i2c_arm=on
gpu_mem=16
max_usb_current=1

# CPU settings (conservative for stability)
arm_freq=1200
over_voltage=2
```

### Device Tree

- **DTB file**: `bcm2710-rpi-3-b-plus.dtb`
- Automatically copied during Stage 2 customization

### Kernel & Firmware

- **Package**: `raspberrypi-kernel` (32-bit armhf)
- **Firmware**: Standard Pi firmware (bootcode.bin, start.elf, fixup.dat)

## Network Performance

Due to USB 2.0 bus limitations:

| Interface | Theoretical | Actual |
|-----------|-------------|--------|
| Ethernet | 1 Gbps | ~300 Mbps |
| WiFi 5GHz | 433 Mbps | ~100 Mbps |
| WiFi 2.4GHz | 150 Mbps | ~50 Mbps |

For higher throughput, consider Raspberry Pi 4B.

## Caching

Base system cache: `cache/pimeleon-rpi3-bullseye-base-v1.tar.gz`

Subsequent builds reuse this cache, reducing build time from ~15 min to ~8 min.

## Known Limitations

- **Ethernet throughput**: Limited to ~300 Mbps (USB 2.0 bottleneck)
- **RAM**: Fixed at 1 GB, no upgrade option
- **USB**: All ports share USB 2.0 bandwidth

## Recommended Use Cases

- Home router (< 300 Mbps internet)
- WiFi access point
- VPN gateway
- Network monitoring
- IoT gateway

## Resources

- [Raspberry Pi 3B+ Product Page](https://www.raspberrypi.com/products/raspberry-pi-3-model-b-plus/)
- [BCM2710 Datasheet](https://datasheets.raspberrypi.com/bcm2835/bcm2835-peripherals.pdf)
- [Pi 3B+ Schematics](https://datasheets.raspberrypi.com/rpi3/raspberry-pi-3-b-plus-reduced-schematics.pdf)

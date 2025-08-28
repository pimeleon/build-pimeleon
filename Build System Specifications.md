# Pi Router Containerized Build System - Technical Specifications

## 1. System Architecture

### 1.1 Container Runtime

- **Primary**: Docker 24.0+ with BuildKit enabled
- **Alternative**: Podman 4.0+ (rootless mode supported)
- **Base Image**: Debian 12 (Bookworm) or Ubuntu 22.04 LTS
- **Architecture**: Multi-arch support (amd64 host, ARM64 target emulation)

### 1.2 Virtualization Stack

- **Hypervisor**: QEMU 7.2+ with KVM acceleration (when available)
- **Management**: Libvirt 9.0+ with system and session modes
- **Emulation**: qemu-system-arm for Raspberry Pi 3B+ (BCM2837)
- **Storage**: qcow2 images with backing store support for efficient snapshots

### 1.3 Network Architecture

```yaml
Networks:
  wan_network:
    type: NAT
    subnet: 10.0.1.0/24
    dhcp: true
    dns: 8.8.8.8, 8.8.4.4
    
  lan_network:
    type: isolated
    subnet: 192.168.100.0/24
    dhcp: false  # Pi Router provides DHCP
    
  mgmt_network:
    type: bridge
    bridge: virbr-mgmt
    subnet: 172.16.0.0/24
    purpose: SSH access and monitoring
```

## 2. Container Components

### 2.1 Build Container

```yaml
Purpose: Create Pi Router images
Tools:
  - debootstrap (Raspbian bootstrap)
  - qemu-user-static (ARM chroot)
  - parted, kpartx (partition management)
  - ansible (configuration management)
Volumes:
  - ./builds:/output (generated images)
  - ./cache:/cache (package cache)
  - ./configs:/configs (Pi Router configs)
```

### 2.2 Test Container

```yaml
Purpose: Run and test Pi Router
Components:
  - libvirtd daemon
  - QEMU ARM system emulation
  - virsh CLI tools
  - network namespaces
Capabilities:
  - CAP_NET_ADMIN (network management)
  - CAP_SYS_ADMIN (VM management)
Devices:
  - /dev/kvm (if available)
  - /dev/net/tun (network)
```

## 3. Build Pipeline

### 3.1 Image Creation Process

```mermaid
graph LR
    A[Base Raspbian] --> B[Mount & Chroot]
    B --> C[Install Packages]
    C --> D[Apply Configs]
    D --> E[Security Hardening]
    E --> F[Cleanup & Shrink]
    F --> G[Generate Checksums]
    G --> H[Compress Image]
```

### 3.2 Build Stages

1. **Stage 1 - Base System**
    - Download Raspbian Lite
    - Create loop devices
    - Bootstrap base system
2. **Stage 2 - Customization**
    - Install Pi Router packages
    - Configure networking
    - Apply security policies
3. **Stage 3 - Optimization**
    - Remove unnecessary packages
    - Clear caches and logs
    - Shrink filesystem
4. **Stage 4 - Packaging**
    - Create final image
    - Generate metadata
    - Compress with xz

## 4. Testing Infrastructure

### 4.1 Test Scenarios

```yaml
smoke_test:
  duration: 5 min
  validates:
    - Boot sequence
    - Network interfaces
    - Basic routing

integration_test:
  duration: 15 min
  validates:
    - DHCP server
    - DNS resolution
    - Firewall rules
    - VPN connectivity

stress_test:
  duration: 30 min
  validates:
    - 50 concurrent clients
    - Bandwidth saturation
    - Memory stability
    - CPU throttling

security_test:
  duration: 20 min
  validates:
    - Port scanning
    - Penetration attempts
    - Service hardening
    - Update mechanism
```

### 4.2 Client VM Specifications

```yaml
test_client:
  os: Alpine Linux 3.18
  memory: 256MB
  network: lan_network
  count: 1-50 (scalable)
  
wan_simulator:
  os: Ubuntu Server 22.04
  memory: 512MB
  network: wan_network
  services:
    - Web server
    - DNS server
    - Speed test endpoint
```

## 5. Development Environment

### 5.1 Directory Structure

```shell
pi-router-build/
├── .devcontainer/          # VSCode devcontainer
│   ├── devcontainer.json
│   └── docker-compose.yml
├── containers/
│   ├── builder/
│   │   ├── Dockerfile
│   │   └── scripts/
│   └── tester/
│       ├── Dockerfile
│       └── libvirt/
├── ansible/
│   ├── playbooks/
│   ├── roles/
│   └── inventory/
├── tests/
│   ├── unit/
│   ├── integration/
│   └── fixtures/
├── configs/
│   ├── network/
│   ├── security/
│   └── services/
├── output/                 # Generated images
├── cache/                  # Build cache
└── docker-compose.yml
```

### 5.2 Resource Requirements

```yaml
Minimum:
  CPU: 4 cores
  RAM: 8GB
  Storage: 50GB
  Network: 10Mbps

Recommended:
  CPU: 8 cores
  RAM: 16GB
  Storage: 100GB SSD
  Network: 100Mbps
  KVM: enabled
```

## 6. CI/CD Integration

### 6.1 Pipeline Stages

```yaml
stages:
  - lint        # Config validation
  - build       # Image creation
  - test        # Automated testing
  - scan        # Security scanning
  - publish     # Release artifacts
  - deploy      # Update servers
```

### 6.2 Artifact Storage

```yaml
artifacts:
  images:
    format: .img.xz
    retention: 90 days
    storage: S3/MinIO
    
  metadata:
    format: JSON
    content:
      - version
      - checksums
      - package list
      - test results
      
  logs:
    format: compressed
    retention: 30 days
```

## 7. Security Specifications

### 7.1 Container Security

- No privileged mode unless required for libvirt
- Minimal capability set (NET_ADMIN, SYS_ADMIN)
- Read-only root filesystem where possible
- Non-root user for build processes
- Secrets management via environment/volumes

### 7.2 Build Security

- GPG signing of images
- Reproducible builds
- SBOM (Software Bill of Materials) generation
- CVE scanning of packages
- Secure boot support preparation

## 8. Performance Targets

### 8.1 Build Performance

- Full build: < 45 minutes
- Incremental build: < 15 minutes
- Parallel builds: 4 concurrent
- Cache hit rate: > 80%

### 8.2 Test Performance

- VM boot time: < 30 seconds
- Network setup: < 10 seconds
- Test client spawn: < 5 seconds/client
- Full test suite: < 60 minutes

## 9. Monitoring & Logging

### 9.1 Metrics Collection

```yaml
metrics:
  build:
    - Duration per stage
    - Package download time
    - Disk usage
    - Cache efficiency
    
  test:
    - VM resource usage
    - Network throughput
    - Test pass/fail rates
    - Performance regression
```

### 9.2 Log Management

- Structured logging (JSON)
- Log levels: DEBUG, INFO, WARN, ERROR
- Centralized collection
- Rotation and compression

## 10. Migration Path

### 10.1 Cloud Deployment

- **AWS**: EC2 with nested virtualization
- **GCP**: Compute Engine with nested KVM
- **Azure**: Dv3/Ev3 series VMs
- **Self-hosted**: Kubernetes with KubeVirt

### 10.2 Scaling Strategy

- Horizontal: Multiple build containers
- Vertical: Increase container resources
- Distributed: Build farm with orchestration

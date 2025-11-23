# Architecture Overview

The Pimeleon Build System is a containerized, multi-stage build pipeline that creates bootable Raspberry Pi images using ARM cross-compilation and QEMU emulation.

## High-Level Architecture

```mermaid
graph TB
    subgraph "Host System (x86_64)"
        A[Docker Engine] --> B[Build Network]
        A --> C[WAN Network]
        A --> D[LAN Network]
        A --> E[Mgmt Network]

        subgraph "Builder Container (Debian 12)"
            F[Build Scripts] --> G[Stage 1: Base]
            G --> H[Stage 2: Customize]
            H --> I[Stage 3: Optimize]
            I --> J[Stage 4: Package]

            K[QEMU User] -.->|ARM Emulation| G
            K -.->|ARM Emulation| H

            L[Ansible] --> H
        end

        subgraph "Tester Container (Ubuntu 22.04)"
            M[QEMU System] --> N[Virtual Pi]
            O[Test Framework] --> N
        end

        subgraph "Dev Container"
            P[Interactive Shell]
            Q[Development Tools]
        end
    end

    subgraph "External Resources"
        R[APT Cache<br/>192.168.76.5:3142]
        S[Raspbian Archive<br/>archive.raspbian.org]
        T[Pi Foundation<br/>archive.raspberrypi.org]
    end

    subgraph "Build Artifacts"
        U[Output Images<br/>output/*.img]
        V[Build Cache<br/>cache/*.tar.gz]
        W[Build Logs<br/>output/*.log]
    end

    F -->|Downloads| R
    F -->|Downloads| S
    F -->|Downloads| T
    J --> U
    G --> V
    F --> W
    M --> O

    style F fill:#4CAF50
    style U fill:#2196F3
    style V fill:#FF9800
```

## System Components

### 1. Container Stack

The system uses three Docker containers, each with a specific purpose:

| Container | Base Image | Purpose | Key Tools |
|-----------|-----------|---------|-----------|
| **builder** | Debian 12 | Main build environment | debootstrap, QEMU, Ansible |
| **tester** | Ubuntu 22.04 | Testing and validation | QEMU System, libvirt, KVM |
| **dev** | Same as builder | Development and debugging | All builder tools + extras |

See [Containers](containers.md) for detailed specifications.

### 2. Build Pipeline

Four-stage pipeline for image creation:

```mermaid
flowchart LR
    A[Start] --> B{Cache<br/>Exists?}
    B -->|Yes| C[Load Cache]
    B -->|No| D[Stage 1:<br/>Bootstrap]

    C --> E[Stage 2:<br/>Customize]
    D --> F{Save<br/>Cache?}
    F -->|Yes| G[Create Cache]
    F -->|No| E
    G --> E

    E --> H{Stage 3<br/>Enabled?}
    H -->|Yes| I[Stage 3:<br/>Optimize]
    H -->|No| K
    I --> J{Stage 4<br/>Enabled?}
    J -->|Yes| K[Stage 4:<br/>Package]
    J -->|No| L

    K --> L[Output<br/>Image]

    style D fill:#4CAF50
    style E fill:#2196F3
    style I fill:#FF9800
    style K fill:#9C27B0
    style L fill:#F44336
```

See [Build Pipeline](build-pipeline.md) for detailed stage descriptions.

### 3. Network Architecture

Four isolated Docker networks for build and test isolation:

```mermaid
graph TB
    subgraph "Docker Networks"
        subgraph "Build Network (build-network)"
            A[Builder Container]
            A -.->|Isolated| B[Build Process]
        end

        subgraph "WAN Network (10.0.1.0/24)"
            C[WAN Gateway<br/>10.0.1.1]
            D[Internet Simulation]
            C --> D
        end

        subgraph "LAN Network (192.168.100.0/24)"
            E[LAN Gateway<br/>192.168.100.1]
            F[Client Simulation]
            E --> F
        end

        subgraph "Mgmt Network (172.16.0.0/24)"
            G[Mgmt Gateway<br/>172.16.0.1]
            H[Management Access]
            G --> H
        end
    end

    subgraph "Host Network"
        I[Host Bridge]
        I --> C
        I --> E
        I --> G
    end

    style A fill:#4CAF50
    style C fill:#2196F3
    style E fill:#FF9800
    style G fill:#9C27B0
```

See [Network Design](networking.md) for configuration details.

## Data Flow

### Build Process Data Flow

```mermaid
sequenceDiagram
    participant U as User
    participant D as Docker Compose
    participant B as Builder Container
    participant Q as QEMU ARM
    participant A as Ansible
    participant O as Output

    U->>D: docker compose run builder
    D->>B: Start container
    B->>B: Check for base cache
    alt Cache exists
        B->>B: Load cache
    else No cache
        B->>Q: Bootstrap ARM rootfs
        Q->>B: ARM binaries executed
        B->>B: Save cache
    end

    B->>A: Run provisioning playbooks
    A->>Q: Execute in ARM chroot
    Q->>A: Configuration applied
    A->>B: Playbook complete

    B->>B: Cleanup and finalize
    B->>O: Write image file
    B->>O: Generate checksums
    B->>O: Write build log
    O->>U: Build complete
```

### Package Download Flow

```mermaid
flowchart TD
    A[Builder Script] --> B{APT Cache<br/>Configured?}

    B -->|Yes| C[Check APT Cache<br/>192.168.76.5:3142]
    B -->|No| D[Direct Download]

    C --> E{Package<br/>in Cache?}
    E -->|Yes| F[Serve from Cache<br/>~100ms]
    E -->|No| G[Download from Mirror]

    G --> H[Cache Package]
    H --> F

    D --> I[Download from Mirror<br/>archive.raspbian.org]

    F --> J[Install Package]
    I --> J

    J --> K[Build Continues]

    style F fill:#4CAF50
    style I fill:#FF9800
    style J fill:#2196F3
```

## Key Technologies

### ARM Emulation

Uses QEMU user-mode emulation for running ARM binaries on x86 hosts:

```mermaid
graph LR
    A[x86 Host] --> B[Linux Kernel]
    B --> C[binfmt_misc]
    C --> D{Binary<br/>Format?}

    D -->|x86| E[Native Execution]
    D -->|ARM| F[QEMU User Mode]

    F --> G[ARM Binary Translation]
    G --> H[x86 Instructions]
    H --> E

    E --> I[Process Output]

    style F fill:#4CAF50
    style G fill:#2196F3
```

**How it works:**

1. Linux kernel detects ARM binary via magic bytes
2. `binfmt_misc` intercepts execution
3. Kernel invokes QEMU user-mode emulator
4. QEMU translates ARM instructions to x86
5. Process executes as if native ARM

### Debootstrap Process

Creates minimal Debian/Raspbian base system:

```mermaid
stateDiagram-v2
    [*] --> Download: First Stage
    Download --> Extract: Download packages
    Extract --> UnpackEssential: Extract archives
    UnpackEssential --> ConfigureEssential: Unpack essential packages

    ConfigureEssential --> Chroot: Second Stage
    Chroot --> UnpackAll: Enter chroot
    UnpackAll --> ConfigureAll: Unpack remaining packages
    ConfigureAll --> Cleanup: Configure all packages

    Cleanup --> [*]: Bootstrap complete

    note right of Download
        Downloads .deb files
        No ARM execution
    end note

    note right of Chroot
        Runs inside ARM chroot
        Requires QEMU
    end note
```

### Ansible Provisioning

Configuration management using Ansible in chroot mode:

```mermaid
flowchart TD
    A[Ansible Playbook] --> B[Pre-tasks]
    B --> C[Base Setup Tasks]
    C --> D[Network Setup Tasks]
    D --> E[Security Hardening Tasks]
    E --> F[Post-tasks]
    F --> G[Handlers]

    subgraph "Base Setup"
        C --> C1[Set Hostname]
        C --> C2[Configure Timezone]
        C --> C3[Install Packages]
        C --> C4[Create Users]
    end

    subgraph "Network Setup"
        D --> D1[systemd-networkd Config]
        D --> D2[DHCP Server]
        D --> D3[WiFi AP]
        D --> D4[Firewall Rules]
    end

    subgraph "Security"
        E --> E1[SSH Hardening]
        E --> E2[fail2ban]
        E --> E3[Audit Rules]
        E --> E4[Auto Updates]
    end

    style A fill:#4CAF50
    style C fill:#2196F3
    style D fill:#FF9800
    style E fill:#9C27B0
```

## Performance Optimizations

### Multi-Layer Caching Strategy

```mermaid
graph TB
    A[Build Request] --> B{Docker Layer<br/>Cache?}
    B -->|Hit| C[Reuse Docker Layer]
    B -->|Miss| D[Build Docker Layer]

    C --> E{Base System<br/>Cache?}
    D --> E

    E -->|Hit| F[Extract Base Cache<br/>cache/*.tar.gz]
    E -->|Miss| G[Run Debootstrap]

    F --> H{APT Package<br/>Cache?}
    G --> H

    H -->|Hit| I[Serve from apt-cacher-ng<br/>~100ms per package]
    H -->|Miss| J[Download from Mirror<br/>~2s per package]

    I --> K[Complete Build]
    J --> K

    style C fill:#4CAF50
    style F fill:#4CAF50
    style I fill:#4CAF50
    style D fill:#FF9800
    style G fill:#FF9800
    style J fill:#FF9800
```

### Cache Efficiency

| Cache Layer | Hit Rate | Time Saved | Storage |
|-------------|----------|------------|---------|
| **Docker Layer** | ~90% | 5 minutes | ~2 GB |
| **Base System** | ~85% | 10 minutes | 149 MB |
| **APT Package** | ~95% | 10 minutes | ~2 GB |
| **Combined** | - | 15-20 minutes | ~4 GB |

## Security Model

### Build-Time Security

```mermaid
graph TD
    A[Build Process] --> B[Non-Root Builder User<br/>UID 1000]
    B --> C[Restricted sudo<br/>Only loop device access]

    A --> D[Container Isolation]
    D --> E[No host filesystem access]
    D --> F[Isolated networks]

    A --> G[Secrets Management]
    G --> H[No secrets in logs]
    G --> I[No secrets in images]
    G --> J[SSH keys from host only]

    style B fill:#4CAF50
    style D fill:#2196F3
    style G fill:#9C27B0
```

### Runtime Security

Generated images include:

- SSH: Root login disabled, key-based auth only
- Firewall: nftables with default-deny policy
- Services: fail2ban, automatic security updates
- Audit: auditd logging for security events
- Users: Non-root 'pi' user with restricted sudo

See the troubleshooting guide for more security details.

## Resource Requirements

### Build System

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| **CPU** | 4 cores | 8 cores | More cores = faster builds |
| **RAM** | 8 GB | 16 GB | Docker + QEMU require memory |
| **Disk** | 50 GB | 100 GB | Includes caches and output |
| **Network** | 10 Mbps | 100 Mbps | For package downloads |

### Generated Images

| Resource | Usage | Notes |
|----------|-------|-------|
| **SD Card** | 8 GB minimum | 4 GB image, leaves room for data |
| **Pi RAM** | 1 GB (Pi 3B+) | Sufficient for routing |
| **Network** | 2-3 interfaces | eth0 (WAN), eth1 (LAN), wlan0 (AP) |

## Component Interactions

```mermaid
graph TB
    subgraph "Build Phase"
        A[docker-compose.yml] --> B[Builder Container]
        B --> C[Build Scripts]
        C --> D[Stage 1: Debootstrap]
        C --> E[Stage 2: Ansible]

        F[configs/] --> E
        G[ansible/playbooks/] --> E
    end

    subgraph "Runtime Phase (on Pi)"
        H[systemd] --> I[systemd-networkd]
        H --> J[isc-dhcp-server]
        H --> K[hostapd]
        H --> L[nftables]
        H --> M[fail2ban]
        H --> N[SSH]

        O[/etc/systemd/network/] --> I
        P[/etc/dhcp/dhcpd.conf] --> J
        Q[/etc/hostapd/hostapd.conf] --> K
        R[/etc/nftables.conf] --> L
    end

    E -.->|Generates| O
    E -.->|Generates| P
    E -.->|Generates| Q
    E -.->|Generates| R

    style B fill:#4CAF50
    style E fill:#2196F3
    style H fill:#9C27B0
```

## Next Steps

<div class="grid cards" markdown>

-   **Container Details**

    Detailed specifications of each container, Dockerfiles, and tools

    [:octicons-arrow-right-24: Containers](containers.md)

-   **Build Pipeline**

    Deep dive into each build stage and what happens

    [:octicons-arrow-right-24: Build Pipeline](build-pipeline.md)

-   **Network Design**

    Network architecture, interfaces, and routing configuration

    [:octicons-arrow-right-24: Network Design](networking.md)

</div>

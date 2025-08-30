# Pi Router Build Container
FROM debian:12-slim AS base

# Build arguments for APT cache configuration
ARG APT_CACHE_SERVER
ARG APT_CACHE_PORT="3142"

# Configure APT cache if server is provided
RUN if [ -n "$APT_CACHE_SERVER" ]; then \
    echo "Acquire::http::Proxy \"http://${APT_CACHE_SERVER}:${APT_CACHE_PORT}\";" > /etc/apt/apt.conf.d/01proxy && \
    echo "Acquire::https::Proxy \"DIRECT\";" >> /etc/apt/apt.conf.d/01proxy && \
    echo "Using APT cache at ${APT_CACHE_SERVER}:${APT_CACHE_PORT}"; \
    fi

# Install base dependencies and build tools with cache mount
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    apt-get update && apt-get install -y --no-install-recommends \
    debootstrap \
    qemu-user-static \
    binfmt-support \
    parted \
    kpartx \
    dosfstools \
    e2fsprogs \
    xz-utils \
    wget \
    curl \
    git \
    gnupg \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv \
    ansible \
    rsync \
    sudo \
    build-essential \
    crossbuild-essential-armhf \
    device-tree-compiler \
    u-boot-tools \
    bc \
    bison \
    flex \
    libssl-dev \
    util-linux \
    coreutils

# Create build user with restricted sudo access
RUN useradd -m -s /bin/bash -u 1000 builder && \
    usermod -a -G disk builder && \
    echo "builder ALL=(ALL) NOPASSWD:SETENV: /usr/bin/mount, /usr/bin/umount, /sbin/losetup, /sbin/kpartx, /usr/sbin/debootstrap, /usr/sbin/chroot, /bin/dd, /sbin/mkfs.*, /sbin/parted, /bin/cp, /bin/rm, /bin/mkdir, /bin/chown, /bin/chmod, /usr/bin/tee, /bin/cat, /bin/tar, /bin/touch, /bin/sed, /bin/ls, /usr/bin/sed, /usr/bin/env, /bin/rmdir, /usr/bin/truncate, /usr/bin/find" >> /etc/sudoers.d/builder && \
    chmod 0440 /etc/sudoers.d/builder

# Set up Python environment
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python packages with cache mount
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip && \
    pip install \
    pyyaml \
    jinja2 \
    requests \
    click \
    rich \
    pytest \
    pytest-cov

# Set up working directories
RUN mkdir -p /output /cache /configs /ansible /scripts && \
    chown -R builder:builder /output /cache /configs /ansible /scripts

# Copy build scripts
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# Cache Debian Buster base for debootstrap (matching production Pi 3B+)
ADD --checksum=sha256:0680cca0de3a9b9e5ae12de8cfde3229749a757ddcee1d0ec3d22ef28f602611 \
    http://deb.debian.org/debian/dists/buster/Release \
    /cache/debian-buster-release

# Set environment variables
ENV BUILD_USER=builder
ENV OUTPUT_DIR=/output
ENV CACHE_DIR=/cache
ENV CONFIG_DIR=/configs
ENV ANSIBLE_DIR=/ansible
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Switch to build user by default
USER builder
WORKDIR /workspace

# Default command
CMD ["/scripts/build.sh"]

# Development stage with additional tools
FROM base AS development

USER root

# Install development and debugging tools with cache mount
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    vim \
    nano \
    htop \
    tmux \
    tree \
    jq \
    shellcheck \
    yamllint \
    ansible-lint \
    strace \
    ltrace \
    gdb \
    tcpdump \
    net-tools \
    iputils-ping \
    dnsutils

USER builder
# Pi Router Build Container
FROM debian:12-slim AS base

# Install base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
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
    && rm -rf /var/lib/apt/lists/*

# Install additional build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    crossbuild-essential-armhf \
    device-tree-compiler \
    u-boot-tools \
    bc \
    bison \
    flex \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Create build user
RUN useradd -m -s /bin/bash -u 1000 builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Set up Python environment
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python packages
RUN pip install --upgrade pip && \
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

# Install development tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    vim \
    nano \
    htop \
    tmux \
    tree \
    jq \
    shellcheck \
    yamllint \
    ansible-lint \
    && rm -rf /var/lib/apt/lists/*

# Install debugging tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    strace \
    ltrace \
    gdb \
    tcpdump \
    net-tools \
    iputils-ping \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*

USER builder
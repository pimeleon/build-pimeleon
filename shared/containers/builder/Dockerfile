# Pimeleon Build Container

# Stage 1: Use pre-built adblock2privoxy image
# Build once with: ./scripts/build-ab2p.sh
# This avoids slow Haskell rebuilds on every docker compose build
FROM pimeleon-adblock2privoxy:latest AS adblock2privoxy-builder

# Stage 2: Main builder image
FROM debian:12-slim AS base

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Build arguments for APT cache configuration
ARG APT_CACHE_SERVER
ARG APT_CACHE_PORT="3142"
ARG PIMELEON_PROFILE="production"
ARG CI=""

# Configure APT resilience and proxy if in CI or development mode
RUN if [ -n "$CI" ] || [ "$PIMELEON_PROFILE" = "development" ]; then \
    # Resilience settings for apt-cacher-ng proxy disconnections
    echo 'Acquire::Retries "3";' > /etc/apt/apt.conf.d/80-retries && \
    echo 'Acquire::http::Pipeline-Depth "0";' >> /etc/apt/apt.conf.d/80-retries && \
    echo 'Acquire::http::Timeout "60";' >> /etc/apt/apt.conf.d/80-retries && \
    if [ -n "$APT_CACHE_SERVER" ]; then \
        echo "Acquire::http::Proxy \"http://${APT_CACHE_SERVER}:${APT_CACHE_PORT}\";" > /etc/apt/apt.conf.d/01proxy && \
        echo "Acquire::https::Proxy \"DIRECT\";" >> /etc/apt/apt.conf.d/01proxy && \
        echo "Using APT cache at ${APT_CACHE_SERVER}:${APT_CACHE_PORT}"; \
    fi; \
    fi

# Install base dependencies and build tools
# APT caching handled by remote apt-cacher-ng at APT_CACHE_SERVER
# Clean local cache after install to reduce image size
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    ansible \
    bc \
    bison \
    binfmt-support \
    build-essential \
    ca-certificates \
    coreutils \
    crossbuild-essential-armhf \
    curl \
    debootstrap \
    device-tree-compiler \
    dosfstools \
    e2fsprogs \
    flex \
    git \
    gnupg \
    iperf3 \
    kpartx \
    libssl-dev \
    parted \
    python3 \
    python3-pip \
    python3-venv \
    qemu-user-static \
    rsync \
    sudo \
    u-boot-tools \
    unzip \
    util-linux \
    wget \
    xz-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 from NodeSource (for UI build)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && corepack enable \
    && corepack prepare pnpm@9 --activate

# Copy adblock2privoxy binary and templates from builder stage
COPY --from=adblock2privoxy-builder /usr/local/bin/adblock2privoxy /usr/local/bin/adblock2privoxy
COPY --from=adblock2privoxy-builder /opt/adblock2privoxy/templates /usr/share/adblock2privoxy/templates

# Create build user with sudo access
RUN groupadd -g 999 docker && \
    useradd -m -s /bin/bash -u 1001 builder && \
    usermod -a -G docker builder && \
    echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/builder && \
    chmod 0440 /etc/sudoers.d/builder

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
    chown -R builder:docker /output /cache /configs /ansible /scripts

# Copy app configs into image (scripts mounted/copied at runtime)
# Build context must be project root (.) for these paths to work
COPY apps/ /workspace/apps/
RUN mkdir -p /workspace && chown -R builder:docker /workspace

# Cache Debian Buster base for debootstrap (matching production Pi 3B+)
ADD --checksum=sha256:8b9ddf0a5c3371b337e68fbfd7034ccf1b0bd3494d4c998a9da14ae8cf4b8c28 \
    http://deb.debian.org/debian/dists/buster/Release \
    /cache/debian-buster-release

# Set environment variables
ENV BUILD_USER=builder
ENV OUTPUT_DIR=/output
ENV CACHE_DIR=/cache
ENV CONFIG_DIR=/configs
ENV ANSIBLE_DIR=/ansible
ENV PYTHONUNBUFFERED=1

# Switch to build user by default
USER builder
WORKDIR /workspace

# Default command
CMD ["/scripts/build.sh"]

# Development stage with additional tools
FROM base AS development

USER root

# Install development and debugging tools
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    ansible-lint \
    dnsutils \
    htop \
    gdb \
    iputils-ping \
    jq \
    jnettop \
    ltrace \
    nano \
    net-tools \
    shellcheck \
    strace \
    tcpdump \
    tmux \
    tree \
    vim \
    yamllint \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER builder

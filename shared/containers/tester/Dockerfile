# Pimeleon Test Container
FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

ARG APT_CACHE_SERVER=""
ARG APT_CACHE_PORT="3142"
ARG PIMELEON_PROFILE="production"
ARG CI=""

# Configure APT resilience and proxy if in CI or development mode
RUN if [ -n "$CI" ] || [ "$PIMELEON_PROFILE" = "development" ]; then \
    # Resilience settings for apt-cacher-ng proxy disconnections
    echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries && \
    echo 'Acquire::http::Pipeline-Depth "0";' >> /etc/apt/apt.conf.d/80-retries && \
    echo 'Acquire::http::Timeout "60";' >> /etc/apt/apt.conf.d/80-retries && \
    if [ -n "$APT_CACHE_SERVER" ]; then \
        echo "Acquire::http::Proxy \"http://${APT_CACHE_SERVER}:${APT_CACHE_PORT}\";" > /etc/apt/apt.conf.d/01proxy && \
        echo "Acquire::https::Proxy \"DIRECT\";" >> /etc/apt/apt.conf.d/01proxy && \
        echo "Using APT cache at ${APT_CACHE_SERVER}:${APT_CACHE_PORT}"; \
    fi; \
    fi

# Install base dependencies and testing tools
RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    qemu-system-arm \
    qemu-utils \
    qemu-efi-aarch64 \
    libvirt-daemon-system \
    libvirt-clients \
    virtinst \
    bridge-utils \
    dnsmasq \
    iptables \
    iproute2 \
    net-tools \
    tcpdump \
    curl \
    wget \
    python3 \
    python3-pip \
    python3-libvirt \
    python3-lxml \
    genisoimage \
    cloud-utils \
    openssh-client \
    sshpass \
    expect \
    jq \
    iperf3 \
    nmap \
    hping3 \
    netcat \
    socat \
    stress-ng \
    apache2-utils \
    siege \
    nikto

# Install Python testing packages with cache mount
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install \
    pytest \
    pytest-testinfra \
    pytest-timeout \
    pytest-xdist \
    pytest-html \
    paramiko \
    requests \
    pexpect \
    netaddr \
    scapy \
    pyyaml \
    python-magic

# Configure libvirt
RUN mkdir -p /var/run/libvirt && \
    mkdir -p /var/lib/libvirt/images && \
    mkdir -p /etc/libvirt/qemu/networks/autostart

# Copy libvirt network configurations
COPY libvirt/networks/*.xml /etc/libvirt/qemu/networks/

# Copy test scripts
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# Create test user
RUN useradd -m -s /bin/bash tester && \
    usermod -aG libvirt,kvm tester

# Set up working directories
RUN mkdir -p /tests /images /results && \
    chown -R tester:tester /tests /results

# Environment variables
ENV LIBVIRT_DEFAULT_URI=qemu:///system
ENV TEST_IMAGE_DIR=/images
ENV TEST_RESULTS_DIR=/results
ENV PYTHONUNBUFFERED=1

# Entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /tests

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/scripts/run-tests.sh"]

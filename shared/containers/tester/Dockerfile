# Pimeleon Test Container
FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

ARG APT_CACHE_SERVER=""
ARG APT_CACHE_PORT="3142"

# Configure APT cache if server is provided
RUN if [ -n "$APT_CACHE_SERVER" ]; then \
    echo "Acquire::http::Proxy \"http://${APT_CACHE_SERVER}:${APT_CACHE_PORT}\";" > /etc/apt/apt.conf.d/01proxy && \
    echo "Acquire::https::Proxy \"DIRECT\";" >> /etc/apt/apt.conf.d/01proxy && \
    echo "Using APT cache at ${APT_CACHE_SERVER}:${APT_CACHE_PORT}"; \
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
    pytest-timeout \
    pytest-xdist \
    paramiko \
    requests \
    pexpect \
    netaddr \
    scapy

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

#!/bin/bash
set -e

# Start libvirtd
echo "Starting libvirtd..."
mkdir -p /var/run/libvirt
libvirtd -d

# Wait for libvirtd to be ready
echo "Waiting for libvirtd to start..."
for _ in {1..30}; do
    if virsh list &>/dev/null; then
        echo "libvirtd is ready"
        break
    fi
    sleep 1
done

# Configure default network if not exists
if ! virsh net-list --all | grep -q default; then
    echo "Creating default network..."
    virsh net-define /etc/libvirt/qemu/networks/default.xml 2>/dev/null
    virsh net-start default 2>/dev/null
    virsh net-autostart default 2>/dev/null || true  # Ignore autostart errors
fi

# Define custom networks
for network in /etc/libvirt/qemu/networks/*.xml; do
    if [[ -f "$network" ]]; then
        network_name=$(basename "$network" .xml)
        if [[ "$network_name" != "default" ]] && ! virsh net-list --all | grep -q "$network_name"; then
            echo "Defining network: $network_name"
            virsh net-define "$network" 2>/dev/null
            virsh net-start "$network_name" 2>/dev/null
            virsh net-autostart "$network_name" 2>/dev/null || true  # Ignore autostart errors
        fi
    fi
done

# Execute the main command
exec "$@"

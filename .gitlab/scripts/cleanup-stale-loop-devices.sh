#!/bin/sh
set -eu

# Clean up stale loop devices and kpartx mappings left behind by interrupted
# Pimeleon image builds. Intended to run in a privileged helper container with
# host /dev mounted.

stale_loops=$(losetup -l -n -O NAME,BACK-FILE 2>/dev/null | grep -E 'pimeleon-.*\.img|/output/pimeleon-.*\.img|/tmp/build' | awk '{print $1}' || true)

if [ -z "${stale_loops}" ]; then
    echo "No stale loop devices found."
    exit 0
fi

echo "Cleaning stale loop devices:"
for loop in ${stale_loops}; do
    echo "  - ${loop}"

    loop_name=$(basename "${loop}")

    # Unmount any lingering partition mounts if they still exist.
    # Check both /dev/mapper (kpartx) and /dev/loopNpM (kernel partition scanning)
    for part in "/dev/mapper/${loop_name}p1" "/dev/mapper/${loop_name}p2" "/dev/${loop_name}p1" "/dev/${loop_name}p2"; do
        if [ -e "${part}" ]; then
            mount_points=$(findmnt -rn -S "${part}" -o TARGET 2>/dev/null || true)
            if [ -n "${mount_points}" ]; then
                echo "    unmounting ${part} mountpoints"
                for mnt in ${mount_points}; do
                    echo "      - ${mnt}"
                    umount "${mnt}" 2>/dev/null || umount -l "${mnt}" 2>/dev/null || true
                done
            fi
        fi
    done

    kpartx -d "${loop}" 2>/dev/null || true
    losetup -d "${loop}" 2>/dev/null || true
done

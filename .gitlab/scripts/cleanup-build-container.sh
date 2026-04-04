#!/bin/sh
set -eu

# Cleanup orphaned build container on job cancel/timeout/failure.
# Called from after_script — always runs regardless of job outcome.
if [ -f .build_container_id ]; then
    CID=$(cat .build_container_id)
    echo "Cleaning up build container: $CID"
    if [ "$(docker inspect --format='{{.State.Running}}' "$CID" 2>/dev/null || echo false)" = "true" ]; then
        docker exec "$CID" bash -lc 'source /scripts/common.sh >/dev/null 2>&1 && cleanup_stale_mounts || true' 2>/dev/null || true
    fi
    docker stop -t 10 "$CID" 2>/dev/null || true
    docker rm -f "$CID" 2>/dev/null || true
    rm -f .build_container_id
fi

# Derive arch-correct builder image from TARGET_PLATFORM
case "${TARGET_PLATFORM:-rpi3-bookworm}" in
    *arm64*) _arch="arm64" ;;
    *)       _arch="armhf" ;;
esac
CLEANUP_IMAGE="${CI_REGISTRY_IMAGE}/builder-${_arch}:latest"

if [ -z "${CI_REGISTRY_IMAGE:-}" ]; then
    # Fallback: try to find a local builder image (e.g. local gitlab-runner without registry)
    CLEANUP_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "builder-armhf|builder-arm64" | head -n 1 || true)
fi

if [ -n "${CLEANUP_IMAGE}" ]; then
    echo "Cleaning up host loop devices (stale and active) using image: ${CLEANUP_IMAGE}"
    # Run a privileged helper container to clean up host loop devices.
    # We mount /dev, /run (for udev/lvm), and /sys to allow the container to manipulate host devices.
    timeout 60 docker run --rm \
        --privileged \
        --user root \
        -v /dev:/dev \
        -v /run:/run \
        -v /sys:/sys \
        -v "$PWD":/workspace \
        -w /workspace \
        "${CLEANUP_IMAGE}" \
        /bin/bash -c '
set -eu

# Clean up ALL loop devices associated with pimeleon images or build artifacts
# This handles both active (from current build) and stale (from previous failures) devices

all_loops=$(losetup -l -n -O NAME,BACK-FILE 2>/dev/null | grep -E "pimeleon|/tmp/build" | awk "{print \$1}" || true)

if [ -z "${all_loops}" ]; then
    echo "No loop devices found."
    exit 0
fi

echo "Cleaning all loop devices:"
for loop in ${all_loops}; do
    echo "  - ${loop}"

    loop_name=$(basename "${loop}")

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

    kpartx -dv "${loop}" 2>/dev/null || true
    losetup -d "${loop}" 2>/dev/null || losetup --detach "${loop}" 2>/dev/null || true
done
' || true
else
    echo "[WARN] No builder image found for host loop cleanup. Loop devices may remain."
fi

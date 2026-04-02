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

CLEANUP_IMAGE="${BUILD_IMAGE:-}"
if [ -z "${CLEANUP_IMAGE}" ]; then
    # Fallback: try to find a local builder image if BUILD_IMAGE is not set (e.g. local gitlab-runner)
    CLEANUP_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "pimeleon-build-builder|pimeleon-builder" | head -n 1 || true)
fi

if [ -n "${CLEANUP_IMAGE}" ]; then
    echo "Cleaning up stale host loop devices using image: ${CLEANUP_IMAGE}"
    # Run a privileged helper container to clean up host loop devices.
    # We mount /dev, /run (for udev/lvm), and /sys to allow the container to manipulate host devices.
    docker run --rm \
        --privileged \
        --user root \
        -v /dev:/dev \
        -v /run:/run \
        -v /sys:/sys \
        -v "$PWD":/workspace \
        -w /workspace \
        "${CLEANUP_IMAGE}" \
        sh /workspace/.gitlab/scripts/cleanup-stale-loop-devices.sh || true
else
    echo "[WARN] No builder image found for host loop cleanup. Stale loop devices may remain."
fi

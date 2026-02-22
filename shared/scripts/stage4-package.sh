#!/bin/bash
set -euo pipefail

# Stage 4: Package image
# Create final compressed image with checksums
# All artifacts are placed directly in OUTPUT_DIR (no subdirectories)

# shellcheck disable=SC1091
# shellcheck disable=SC1091
source /scripts/common.sh

# Setup cleanup trap for error handling
trap 'cleanup_on_exit' EXIT ERR INT TERM

WORK_DIR=$1
IMAGE_PATH=$2

log_info "Starting image packaging"

# Generate checksums
log_info "Generating checksums"
cd "$(dirname "${IMAGE_PATH}")"
md5sum "$(basename "${IMAGE_PATH}")" > "${IMAGE_PATH}.md5"
sha256sum "$(basename "${IMAGE_PATH}")" > "${IMAGE_PATH}.sha256"

# Generate metadata JSON
generate_metadata "${IMAGE_PATH}"

# Create software bill of materials
log_info "Creating software bill of materials"
MOUNT_POINT="${WORK_DIR}/mount"
mount_image "${IMAGE_PATH}" "${MOUNT_POINT}"
LOOP_DEVICE="${CLEANUP_LOOP_DEVICE}"
setup_chroot "${MOUNT_POINT}"

# Get package list
chroot_run "${MOUNT_POINT}" dpkg -l > "${IMAGE_PATH}.packages.txt"

# Get version information
cat > "${IMAGE_PATH}.version.txt" <<EOF
Build Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Raspbian Version: ${RASPBIAN_VERSION:-bookworm}
Kernel Version: $(chroot_run "${MOUNT_POINT}" uname -r || echo "unknown")
Pi Model: ${PIMELEON_RPI_MODEL:-3B+}
Builder Version: 1.0.0
EOF

cleanup_chroot "${MOUNT_POINT}"
unmount_image "${MOUNT_POINT}" "${LOOP_DEVICE}"

# Compress image
log_info "Compressing image with xz"
COMPRESSION_LEVEL="${IMAGE_COMPRESSION_LEVEL:-6}"

# Use parallel xz if available
if command -v pixz &> /dev/null; then
    log_info "Using pixz for parallel compression"
    pixz -"${COMPRESSION_LEVEL}" < "${IMAGE_PATH}" > "${IMAGE_PATH}.xz"
else
    log_info "Using xz for compression (this may take a while)"
    xz -"${COMPRESSION_LEVEL}" -T 0 -c "${IMAGE_PATH}" > "${IMAGE_PATH}.xz"
fi

# Generate compressed image checksums
md5sum "$(basename "${IMAGE_PATH}".xz)" > "${IMAGE_PATH}.xz.md5"
sha256sum "$(basename "${IMAGE_PATH}".xz)" > "${IMAGE_PATH}.xz.sha256"

# Keep uncompressed image for easy flashing
# Compressed version is also available as .xz
log_info "Keeping uncompressed image: ${IMAGE_PATH}"

# Final summary
log_info "Packaging completed!"
log_info "Compressed image: ${IMAGE_PATH}.xz ($(du -h "${IMAGE_PATH}.xz" | cut -f1))"
log_info "Uncompressed image: ${IMAGE_PATH}"

log_info "Stage 4 completed successfully"

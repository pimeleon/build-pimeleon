#!/bin/bash
set -euo pipefail

# Stage 4: Package image
# Create final compressed image with checksums

source /scripts/common.sh

WORK_DIR=$1
IMAGE_PATH=$2

log_info "Starting image packaging"

# Generate checksums
log_info "Generating checksums"
cd "$(dirname ${IMAGE_PATH})"
md5sum "$(basename ${IMAGE_PATH})" > "${IMAGE_PATH}.md5"
sha256sum "$(basename ${IMAGE_PATH})" > "${IMAGE_PATH}.sha256"

# Create software bill of materials
log_info "Creating software bill of materials"
MOUNT_POINT="${WORK_DIR}/mount"
LOOP_DEVICE=$(mount_image "${IMAGE_PATH}" "${MOUNT_POINT}")
setup_chroot "${MOUNT_POINT}"

# Get package list
chroot_run "${MOUNT_POINT}" dpkg -l > "${IMAGE_PATH}.packages.txt"

# Get version information
cat > "${IMAGE_PATH}.version.txt" <<EOF
Build Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Raspbian Version: ${RASPBIAN_VERSION}
Kernel Version: $(chroot_run "${MOUNT_POINT}" uname -r || echo "unknown")
Pi Model: ${RPI_MODEL}
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
    pixz -${COMPRESSION_LEVEL} < "${IMAGE_PATH}" > "${IMAGE_PATH}.xz"
else
    log_info "Using xz for compression (this may take a while)"
    xz -${COMPRESSION_LEVEL} -T 0 -c "${IMAGE_PATH}" > "${IMAGE_PATH}.xz"
fi

# Generate compressed image checksums
md5sum "$(basename ${IMAGE_PATH}.xz)" > "${IMAGE_PATH}.xz.md5"
sha256sum "$(basename ${IMAGE_PATH}.xz)" > "${IMAGE_PATH}.xz.sha256"

# Create release archive
log_info "Creating release archive"
RELEASE_NAME="pimeleon-$(date +%Y%m%d-%H%M%S)"
RELEASE_DIR="${OUTPUT_DIR}/${RELEASE_NAME}"
mkdir -p "${RELEASE_DIR}"

# Copy all artifacts
cp "${IMAGE_PATH}.xz" "${RELEASE_DIR}/"
cp "${IMAGE_PATH}.xz.md5" "${RELEASE_DIR}/"
cp "${IMAGE_PATH}.xz.sha256" "${RELEASE_DIR}/"
cp "${IMAGE_PATH}.metadata.json" "${RELEASE_DIR}/"
cp "${IMAGE_PATH}.packages.txt" "${RELEASE_DIR}/"
cp "${IMAGE_PATH}.version.txt" "${RELEASE_DIR}/"

# Create README for the release
cat > "${RELEASE_DIR}/README.txt" <<EOF
Pimeleon Image Release
======================

Release: ${RELEASE_NAME}
Date: $(date)

Contents:
- $(basename ${IMAGE_PATH}.xz) - Compressed Pimeleon image
- *.md5, *.sha256 - Checksum files
- metadata.json - Build metadata
- packages.txt - Installed package list
- version.txt - Version information

Installation:
1. Verify checksums:
   $ sha256sum -c $(basename ${IMAGE_PATH}.xz.sha256)

2. Decompress image:
   $ xz -d $(basename ${IMAGE_PATH}.xz)

3. Write to SD card:
   $ sudo dd if=$(basename ${IMAGE_PATH}) of=/dev/sdX bs=4M status=progress

4. Boot your Raspberry Pi with the SD card

Default credentials:
- Username: pi
- Password: raspberry

IMPORTANT: Change the default password on first login!

For more information, visit: https://github.com/your-repo/pimeleon
EOF

# Create tarball of release
cd "${OUTPUT_DIR}"
tar -czf "${RELEASE_NAME}.tar.gz" "${RELEASE_NAME}/"

# Cleanup uncompressed image to save space
if [[ -f "${IMAGE_PATH}.xz" ]]; then
    log_info "Removing uncompressed image to save space"
    rm -f "${IMAGE_PATH}"
fi

# Final summary
log_info "Packaging completed!"
log_info "Release archive: ${OUTPUT_DIR}/${RELEASE_NAME}.tar.gz"
log_info "Compressed image size: $(du -h ${RELEASE_DIR}/$(basename ${IMAGE_PATH}.xz) | cut -f1)"

log_info "Stage 4 completed successfully"

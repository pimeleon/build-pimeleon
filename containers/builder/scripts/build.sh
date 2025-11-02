#!/bin/bash
set -euo pipefail

# Pi Router Build Script
# Main entry point for building Pi Router images

# Source common functions
source /scripts/common.sh

# Configuration
WORK_DIR="/tmp/build"
IMAGE_NAME="pi-router-$(date +%Y%m%d-%H%M%S).img"
IMAGE_PATH="${OUTPUT_DIR}/${IMAGE_NAME}"
LOG_FILE="${OUTPUT_DIR}/build-$(date +%Y%m%d-%H%M%S).log"

# Default values and export for all stages
export PIROUTER_RPI_MODEL="${PIROUTER_RPI_MODEL:-3B+}"
export PIROUTER_IMAGE_SIZE="${PIROUTER_IMAGE_SIZE:-4G}"
export RASPBIAN_VERSION="${RASPBIAN_VERSION:-buster}"
export RASPBIAN_MIRROR="${RASPBIAN_MIRROR:-http://archive.raspbian.org/raspbian/}"

# Export APT cache configuration for all stages
export APT_CACHE_SERVER="${APT_CACHE_SERVER:-}"
export APT_CACHE_PORT="${APT_CACHE_PORT:-3142}"

# Initialize logging
exec > >(tee -a "${LOG_FILE}")
exec 2>&1

log_info "Pi Router Build System"
log_info "====================="
log_info "Build started at: $(date)"
log_info "Output directory: ${OUTPUT_DIR}"
log_info "Cache directory: ${CACHE_DIR}"
log_info "Image name: ${IMAGE_NAME}"

# Check prerequisites
log_section "Checking prerequisites"
check_prerequisites

# Create work directory
log_section "Setting up build environment"
sudo rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Stage 1: Base System
log_section "Stage 1: Creating base system"
/scripts/stage1-base.sh "${WORK_DIR}" "${IMAGE_PATH}" "${PIROUTER_IMAGE_SIZE}"

# Stage 2: Customization
log_section "Stage 2: Customizing system"
/scripts/stage2-customize.sh "${WORK_DIR}" "${IMAGE_PATH}"

# Stage 3: Optimization (TEMPORARILY DISABLED FOR TESTING)
# log_section "Stage 3: Optimizing image"
# /scripts/stage3-optimize.sh "${WORK_DIR}" "${IMAGE_PATH}"

# Stage 4: Packaging (TEMPORARILY DISABLED FOR TESTING)
# log_section "Stage 4: Packaging image"
# /scripts/stage4-package.sh "${WORK_DIR}" "${IMAGE_PATH}"

# Generate metadata
log_section "Generating metadata"
generate_metadata "${IMAGE_PATH}"

# Cleanup
log_section "Cleaning up"
sudo rm -rf "${WORK_DIR}"

# Summary
log_info ""
log_info "Build completed successfully!"
log_info "Image: ${IMAGE_PATH}"
log_info "Size: $(du -h "${IMAGE_PATH}" | cut -f1)"
log_info "Compressed: ${IMAGE_PATH}.xz"
log_info "Build duration: $SECONDS seconds"

exit 0
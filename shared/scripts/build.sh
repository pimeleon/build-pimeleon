#!/bin/bash
set -euo pipefail

# Pimeleon Build Script - Monorepo Version
# Main entry point for building Pimeleon images

export PYTHONUNBUFFERED=1

# Source common functions
source /scripts/common.sh

# Setup cleanup trap for error handling
trap cleanup_on_exit EXIT ERR INT

# =============================================================================
# App Configuration
# =============================================================================

# Validate PIMELEON_APP is set
if [[ -z "${PIMELEON_APP:-}" ]]; then
    log_error "PIMELEON_APP environment variable is required"
    list_apps
    exit 1
fi

# Load app configuration
load_app_config "${PIMELEON_APP}"

# =============================================================================
# Build Configuration
# =============================================================================

WORK_DIR="/tmp/build"
IMAGE_NAME="pimeleon-${PIMELEON_APP}-$(date +%Y%m%d-%H%M%S).img"
IMAGE_PATH="${OUTPUT_DIR}/${IMAGE_NAME}"
LOG_FILE="${OUTPUT_DIR}/build-${PIMELEON_APP}-$(date +%Y%m%d-%H%M%S).log"

# Track image path for cleanup on failure
export CLEANUP_IMAGE_PATH="${IMAGE_PATH}"

# Build profile and APT cache (can be overridden by environment)
export PIMELEON_PROFILE="${PIMELEON_PROFILE:-development}"
export RASPBIAN_MIRROR="${RASPBIAN_MIRROR:-http://archive.raspbian.org/raspbian/}"
export APT_PROXY="${APT_PROXY:-}"

# =============================================================================
# Build Process
# =============================================================================

# Initialize logging (use stdbuf for line-buffered output)
# Note: exec > >(tee ...) disabled to prevent process substitution issues with sync
# exec > >(stdbuf -oL tee -a "${LOG_FILE}")
# exec 2>&1

log_info "Pimeleon Build System (Monorepo)"
log_info "================================="
log_info "Build started at: $(date)"
log_info "App: ${PIMELEON_APP}"
log_info "Profile: ${PIMELEON_PROFILE}"
log_info "Model: ${PIMELEON_RPI_MODEL}, Arch: ${RPI_ARCH}, Debian: ${RASPBIAN_VERSION}"
log_info "Image: ${PIMELEON_IMAGE_SIZE}, Output: ${OUTPUT_DIR}"

# Check prerequisites
log_section "Checking prerequisites"
check_prerequisites

# Cleanup stale mounts from previous failed builds (skip in CI — fresh container each run)
if [[ "${CI:-}" != "true" ]]; then
    log_section "Checking for stale mounts"
    cleanup_stale_mounts
fi

# Create work directory
log_section "Setting up build environment"
sudo rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Stage 1: Base System
log_section "Stage 1: Creating base system"
/scripts/stage1-base.sh "${WORK_DIR}" "${IMAGE_PATH}" "${PIMELEON_IMAGE_SIZE}"

# Stage 2: Customization
log_section "Stage 2: Customizing system"
/scripts/stage2-customize.sh "${WORK_DIR}" "${IMAGE_PATH}"

# Stage 3: Optimization (enable services + cleanup)
log_section "Stage 3: Optimizing image"
/scripts/stage3-optimize.sh "${WORK_DIR}" "${IMAGE_PATH}"

# Stage 4: Packaging
log_section "Stage 4: Packaging image"
/scripts/stage4-package.sh "${WORK_DIR}" "${IMAGE_PATH}"

# Generate metadata
log_section "Generating metadata"
generate_metadata "${IMAGE_PATH}"

# Cleanup
log_section "Cleaning up"
sudo rm -rf "${WORK_DIR}"

# Summary
log_info ""
log_info "Build completed successfully!"
log_info "App: ${PIMELEON_APP}"
log_info "Image: ${IMAGE_PATH}"
log_info "Size: $(du -h "${IMAGE_PATH}" | cut -f1)"
log_info "Build duration: $SECONDS seconds"

exit 0

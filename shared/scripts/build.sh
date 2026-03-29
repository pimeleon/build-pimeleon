#!/bin/bash
set -euo pipefail
set -E

# Pimeleon Build Script - Monorepo Version
# Main entry point for building Pimeleon images

export PYTHONUNBUFFERED=1

# Source common functions
# shellcheck disable=SC1091
# shellcheck disable=SC1091
source /scripts/common.sh

# Setup cleanup trap for error handling
trap 'cleanup_on_exit' EXIT ERR INT TERM

# =============================================================================
# App Configuration
# =============================================================================

# Validate TARGET_PLATFORM is set
if [[ -z "${TARGET_PLATFORM:-}" ]]; then
    log_error "TARGET_PLATFORM environment variable is required"
    list_apps
    exit 1
fi

# Load app configuration
load_app_config "${TARGET_PLATFORM}"

# =============================================================================
# Build Configuration
# =============================================================================

WORK_DIR="/tmp/build"
BUILD_TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Split TARGET_PLATFORM (e.g., rpi3-bookworm) into device and os
DEVICE_NAME="${TARGET_PLATFORM%%-*}"
OS_NAME="${TARGET_PLATFORM##*-}"

# Determine image name based on build type
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")

# Helper to get version from git tag
get_git_tag_version() {
    # On exact tag - use tag (strip v prefix)
    if version=$(git describe --tags --exact-match HEAD 2>/dev/null); then
        echo "${version#v}"
        return 0
    fi
    return 1
}

if [ -n "${PIMELEON_VERSION:-}" ]; then
    IMAGE_VERSION="${PIMELEON_VERSION}"
    # Release build (or tagged CI build): pimeleon-{device}-{version}-{os}.img
    IMAGE_NAME="pimeleon-${DEVICE_NAME}-${IMAGE_VERSION}-${OS_NAME}.img"
elif IMAGE_VERSION=$(get_git_tag_version); then
    # Git tag build: pimeleon-{device}-{version}-{os}.img
    IMAGE_NAME="pimeleon-${DEVICE_NAME}-${IMAGE_VERSION}-${OS_NAME}.img"
else
    # Development build: pimeleon-{device}-{version}-{os}-{commit}.img
    # Calculate version from conventional commits
    if [ -f "/scripts/get-next-version.sh" ]; then
# shellcheck disable=SC1091
        source /scripts/get-next-version.sh
        IMAGE_VERSION=$(get_next_version "${TARGET_PLATFORM:-}")
    else
        IMAGE_VERSION="0.0.0"
    fi
    IMAGE_NAME="pimeleon-${DEVICE_NAME}-${IMAGE_VERSION}-${OS_NAME}-${COMMIT_HASH}.img"
fi
IMAGE_PATH="${OUTPUT_DIR}/${IMAGE_NAME}"
LOG_FILE="${OUTPUT_DIR}/build-${TARGET_PLATFORM}-${BUILD_TIMESTAMP}.log"

# Clean up old images for the same platform before starting to avoid clutter
log_info "Cleaning up old images for ${TARGET_PLATFORM}..."
# Using safe_rm to be consistent with project standards
# pimeleon-{device}-*-{os}.img covers all version/commit variants
safe_rm "${OUTPUT_DIR}/pimeleon-${DEVICE_NAME}-*-${OS_NAME}.img"*
# Clean up old logs for this platform except the one we're about to create
find "${OUTPUT_DIR}" -name "build-${TARGET_PLATFORM}-*.log" -not -name "$(basename "${LOG_FILE}")" -delete 2>/dev/null || true

# Track image path for cleanup on failure
export CLEANUP_IMAGE_PATH="${IMAGE_PATH}"

# Build profile and APT cache (can be overridden by environment)
export PIMELEON_PROFILE="${PIMELEON_PROFILE:-development}"
export RASPBIAN_MIRROR="${RASPBIAN_MIRROR:-http://archive.raspbian.org/raspbian/}"
export APT_PROXY="${APT_PROXY:-}"

# =============================================================================
# Build Process
# =============================================================================

# Initialize logging
# Use standard redirection to capture all output to both console and log file
exec > >(tee -a "${LOG_FILE}") 2>&1

log_info "Pimeleon Build System (Monorepo)"
log_info "================================="
log_info "Build started at: $(date)"
log_info "App: ${TARGET_PLATFORM}"
log_info "Version: ${IMAGE_VERSION}"
log_info "Profile: ${PIMELEON_PROFILE}"
log_info "Model: ${PIMELEON_RPI_MODEL}, Arch: ${RPI_ARCH}, Debian: ${RASPBIAN_VERSION}"
log_info "Image: ${PIMELEON_IMAGE_SIZE}, Output: ${OUTPUT_DIR}"

# Validate environment
validate_build_environment

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
safe_rm "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Stage 1: Base System
log_section "Stage 1: Creating base system"
DEBUG="${DEBUG:-0}" /scripts/stage1-base.sh "${WORK_DIR}" "${IMAGE_PATH}" "${PIMELEON_IMAGE_SIZE}"

# Stage 2: Customization
log_section "Stage 2: Customizing system"
DEBUG="${DEBUG:-0}" /scripts/stage2-customize.sh "${WORK_DIR}" "${IMAGE_PATH}"

# Stage 3: Optimization (enable services + cleanup)
log_section "Stage 3: Optimizing image"
DEBUG="${DEBUG:-0}" /scripts/stage3-optimize.sh "${WORK_DIR}" "${IMAGE_PATH}"

# Stage 4: Packaging and Metadata (CI only)
if [[ -n "${CI:-}" ]]; then
    log_section "Stage 4: Packaging image"
    /scripts/stage4-package.sh "${WORK_DIR}" "${IMAGE_PATH}"
else
    log_info "Skipping Stage 4 (Packaging) and Metadata generation for local build"
fi

# Cleanup
log_section "Cleaning up"
safe_rm "${WORK_DIR}"

# Summary
log_info ""
log_info "Build completed successfully!"
log_info "App: ${TARGET_PLATFORM}"
log_info "Image: ${IMAGE_PATH}"
log_info "Size: $(du -h "${IMAGE_PATH}" | cut -f1)"
log_info "Build duration: $SECONDS seconds"

exit 0

#!/bin/bash
# Pimeleon Local Build Script
# Runs build directly on host without Docker container
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILDER_SCRIPTS="${PROJECT_ROOT}/containers/builder/scripts"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_section() { echo -e "\n${GREEN}=== $* ===${NC}"; }

# Default configuration
export PIMELEON_RPI_MODEL="${PIMELEON_RPI_MODEL:-3B+}"
export PIMELEON_IMAGE_SIZE="${PIMELEON_IMAGE_SIZE:-4G}"
export PIMELEON_PROFILE="${PIMELEON_PROFILE:-development}"
export RASPBIAN_VERSION="${RASPBIAN_VERSION:-bullseye}"
export RASPBIAN_MIRROR="${RASPBIAN_MIRROR:-http://archive.raspbian.org/raspbian/}"
export APT_CACHE_SERVER="${APT_CACHE_SERVER:-}"
export APT_CACHE_PORT="${APT_CACHE_PORT:-3142}"
export DEBIAN_FRONTEND=noninteractive

# Directories
export OUTPUT_DIR="${PROJECT_ROOT}/output"
export CACHE_DIR="${PROJECT_ROOT}/cache"
export CONFIG_DIR="${PROJECT_ROOT}/configs"
export ANSIBLE_DIR="${PROJECT_ROOT}/ansible"

WORK_DIR="/tmp/pimeleon-build"
IMAGE_NAME="pimeleon-$(date +%Y%m%d-%H%M%S).img"
IMAGE_PATH="${OUTPUT_DIR}/${IMAGE_NAME}"
LOG_FILE="${OUTPUT_DIR}/build-local-$(date +%Y%m%d-%H%M%S).log"

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (for loop devices and chroot)"
        log_info "Run with: sudo $0"
        exit 1
    fi
}

# Check dependencies
check_deps() {
    log_section "Checking dependencies"
    if ! "${SCRIPT_DIR}/check-local-deps.sh"; then
        log_error "Missing dependencies. Run: ${SCRIPT_DIR}/check-local-deps.sh --install"
        exit 1
    fi
}

# Source common functions from builder scripts
source_common() {
    log_info "Loading common functions..."

    # Export paths for common.sh
    export OUTPUT_DIR CACHE_DIR CONFIG_DIR ANSIBLE_DIR

    # shellcheck source=/dev/null
    source "${BUILDER_SCRIPTS}/common.sh"
}

# Main build process
main() {
    local start_time=$SECONDS

    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║           Pimeleon Local Build System                     ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""

    # Initialize logging
    mkdir -p "${OUTPUT_DIR}"
    exec > >(tee -a "${LOG_FILE}")
    exec 2>&1

    log_info "Build started at: $(date)"
    log_info "Profile: ${PIMELEON_PROFILE}"
    log_info "Pi Model: ${PIMELEON_RPI_MODEL}"
    log_info "Debian Version: ${RASPBIAN_VERSION}"
    log_info "Output: ${OUTPUT_DIR}"
    log_info "Log: ${LOG_FILE}"

    check_root
    check_deps
    source_common

    # Create work directory
    log_section "Setting up build environment"
    rm -rf "${WORK_DIR}"
    mkdir -p "${WORK_DIR}"
    mkdir -p "${OUTPUT_DIR}"
    mkdir -p "${CACHE_DIR}"
    cd "${WORK_DIR}"

    # Stage 1: Base System
    log_section "Stage 1: Creating base system"
    "${BUILDER_SCRIPTS}/stage1-base.sh" "${WORK_DIR}" "${IMAGE_PATH}" "${PIMELEON_IMAGE_SIZE}"

    # Stage 2: Customization
    log_section "Stage 2: Customizing system"
    "${BUILDER_SCRIPTS}/stage2-customize.sh" "${WORK_DIR}" "${IMAGE_PATH}"

    # Stage 3: Optimization (if enabled)
    if [[ "${ENABLE_STAGE3:-false}" == "true" ]]; then
        log_section "Stage 3: Optimizing image"
        "${BUILDER_SCRIPTS}/stage3-optimize.sh" "${WORK_DIR}" "${IMAGE_PATH}"
    else
        log_warn "Stage 3 skipped (set ENABLE_STAGE3=true to enable)"
    fi

    # Stage 4: Packaging (if enabled)
    if [[ "${ENABLE_STAGE4:-false}" == "true" ]]; then
        log_section "Stage 4: Packaging image"
        "${BUILDER_SCRIPTS}/stage4-package.sh" "${WORK_DIR}" "${IMAGE_PATH}"
    else
        log_info "Stage 4 skipped (set ENABLE_STAGE4=true to enable)"
    fi

    # Generate metadata
    log_section "Generating metadata"
    generate_metadata "${IMAGE_PATH}"

    # Cleanup
    log_section "Cleaning up"
    rm -rf "${WORK_DIR}"

    # Summary
    local duration=$((SECONDS - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    echo ""
    log_success "Build completed successfully!"
    echo ""
    echo "  Image:    ${IMAGE_PATH}"
    echo "  Size:     $(du -h "${IMAGE_PATH}" | cut -f1)"
    echo "  Duration: ${minutes}m ${seconds}s"
    echo "  Log:      ${LOG_FILE}"
    echo ""

    # Show password location if exists
    if [[ -f "${OUTPUT_DIR}/pi-initial-password.txt" ]]; then
        log_warn "Initial password saved to: ${OUTPUT_DIR}/pi-initial-password.txt"
    fi
}

# Help
show_help() {
    cat << EOF
Pimeleon Local Build Script

Usage: sudo $0 [OPTIONS]

Options:
    -h, --help              Show this help
    -p, --profile PROFILE   Build profile (development|production)
    -m, --model MODEL       Pi model (3B+|4B)
    -v, --version VERSION   Debian version (bullseye|bookworm|trixie)
    --with-cache SERVER     APT cache server IP

Environment Variables:
    PIMELEON_PROFILE        Build profile (default: development)
    PIMELEON_RPI_MODEL      Pi model (default: 3B+)
    PIMELEON_IMAGE_SIZE     Image size (default: 4G)
    RASPBIAN_VERSION        Debian version (default: bullseye)
    APT_PROXY               APT proxy (host:port)
    ENABLE_STAGE3           Enable optimization stage (default: false)
    ENABLE_STAGE4           Enable packaging stage (default: false)

Examples:
    # Development build (default)
    sudo $0

    # Production build
    sudo $0 --profile production

    # With APT cache
    sudo $0 --with-cache 192.168.76.5

    # Pi 4B with Bookworm
    sudo $0 --model 4B --version bookworm
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--profile)
            export PIMELEON_PROFILE="$2"
            shift 2
            ;;
        -m|--model)
            export PIMELEON_RPI_MODEL="$2"
            shift 2
            ;;
        -v|--version)
            export RASPBIAN_VERSION="$2"
            shift 2
            ;;
        --with-cache)
            export APT_PROXY="$2:3142"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

main "$@"

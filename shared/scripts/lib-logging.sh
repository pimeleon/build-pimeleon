#!/bin/bash
# Pimeleon Logging Library
# Centralized logging functions and color definitions

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Internal generic log function
_pimeleon_log() {
    local color="$1"
    local level="$2"
    shift 2
    echo -e "${color}[${level}]${NC} $*"
}

# Public logging functions
log_info() {
    _pimeleon_log "${BLUE}" "INFO" "$*"
}

log_success() {
    _pimeleon_log "${GREEN}" "SUCCESS" "$*"
}

log_warn() {
    _pimeleon_log "${YELLOW}" "WARN" "$*"
}

log_error() {
    _pimeleon_log "${RED}" "ERROR" "$*"
}

log_section() {
    echo -e "\n${GREEN}==>${NC} $*"
}

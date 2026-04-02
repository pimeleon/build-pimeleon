#!/bin/sh
set -eu

# Resolve CI build versions.
# Usage:
#   resolve-version.sh base <target_platform>
#   resolve-version.sh package <target_platform>

mode="${1:-}"
platform="${2:-${TARGET_PLATFORM:-}}"

[ -n "${mode}" ] || { echo "Usage: $0 <base|package> <target_platform>" >&2; exit 1; }
[ -n "${platform}" ] || { echo "Error: target platform is required" >&2; exit 1; }

SCRIPTS_DIR="./shared/scripts"
[ ! -f "./scripts/build.sh" ] || SCRIPTS_DIR="./scripts"

chmod +x "${SCRIPTS_DIR}/get-next-version.sh"
base_version=$("${SCRIPTS_DIR}/get-next-version.sh" "${platform}")

case "${mode}" in
    base)
        echo "${base_version}"
        ;;
    package)
        if [ -n "${CI_COMMIT_TAG:-}" ]; then
            echo "${CI_COMMIT_TAG}"
        else
            echo "${platform}-v${base_version}"
        fi
        ;;
    *)
        echo "Error: unknown mode '${mode}'" >&2
        exit 1
        ;;
esac

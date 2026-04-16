#!/bin/sh
set -eu

# Check whether a Pimeleon package version already exists in the GitLab package registry.
# Exit codes:
#   0 => package exists
#   1 => package does not exist
#   2 => registry query failed

SCRIPT_DIR="$(dirname "$0")"
. "${SCRIPT_DIR}/../../shared/scripts/lib-api.sh"

package_version="${1:-}"
[ -n "${package_version}" ] || { echo "[ERROR] package version is required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq is required" >&2; exit 2; }

_body=$(gitlab_api_get \
    "/projects/${GITLAB_PROJECT}/packages?package_name=pimeleon&package_version=${package_version}") || exit 2

_count=$(printf '%s' "$_body" | jq 'length' 2>/dev/null) || _count=0
if [ "${_count:-0}" -gt 0 ]; then
    exit 0
fi
exit 1

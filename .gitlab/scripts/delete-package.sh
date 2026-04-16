#!/bin/sh
set -eu

# Delete a Pimeleon package version from the GitLab package registry.
# Usage: delete-package.sh <package_version>
#
# Exit codes:
#   0 => package deleted or does not exist
#   1 => delete failed

SCRIPT_DIR="$(dirname "$0")"
. "${SCRIPT_DIR}/../../shared/scripts/lib-api.sh"

package_version="${1:-}"

[ -n "${package_version}" ] || { echo "[ERROR] package version is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq is required" >&2; exit 1; }
[ -n "${GITLAB_DEPLOY_TOKEN:-}" ] || { echo "[ERROR] GITLAB_DEPLOY_TOKEN is not set" >&2; exit 1; }

echo "[INFO] Checking for existing package ${package_version} to delete..."

packages_result=$(gitlab_api_get \
    "/projects/${GITLAB_PROJECT}/packages?package_name=pimeleon&package_version=${package_version}") || exit 1
package_id=$(printf '%s' "${packages_result}" | \
    jq -r 'first(.[] | .id | tostring) // empty' 2>/dev/null)

if [ -z "${package_id}" ]; then
    echo "[INFO] No existing package version ${package_version} found. Nothing to delete."
    exit 0
fi

echo "[INFO] Deleting package ${package_version} (ID: ${package_id})..."
gitlab_api_delete "/projects/${GITLAB_PROJECT}/packages/${package_id}" || exit 1

echo "[SUCCESS] Package version ${package_version} deleted."

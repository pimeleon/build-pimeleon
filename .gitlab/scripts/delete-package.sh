#!/bin/sh
set -eu

# Delete a Pimeleon package version from the GitLab package registry.
# Usage: delete-package.sh <package_version>
#
# Exit codes:
#   0 => package deleted or does not exist
#   1 => delete failed

package_version="${1:-}"

[ -n "${package_version}" ] || { echo "[ERROR] package version is required" >&2; exit 1; }
[ -n "${CI_API_V4_URL:-}" ] || { echo "[ERROR] CI_API_V4_URL is not set" >&2; exit 1; }
[ -n "${CI_PROJECT_ID:-}" ] || { echo "[ERROR] CI_PROJECT_ID is not set" >&2; exit 1; }
[ -n "${CI_JOB_TOKEN:-}" ] || { echo "[ERROR] CI_JOB_TOKEN is not set" >&2; exit 1; }

echo "[INFO] Checking for existing package ${package_version} to delete..."

packages_url="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages?package_name=pimeleon&package_version=${package_version}"
packages_response=$(curl -sk -w "\n%{http_code}" --header "JOB-TOKEN: ${CI_JOB_TOKEN}" "${packages_url}")
packages_status=$(echo "${packages_response}" | tail -1)
packages_result=$(echo "${packages_response}" | sed '$d')

if [ "${packages_status}" != "200" ]; then
    echo "[ERROR] Package lookup failed for ${package_version}: HTTP ${packages_status}" >&2
    exit 1
fi

package_id=$(printf "%s" "${packages_result}" | grep -o '"id":[[:space:]]*[0-9]\+' | head -1 | grep -o '[0-9]\+' || true)

if [ -z "${package_id}" ]; then
    echo "[INFO] No existing package version ${package_version} found. Nothing to delete."
    exit 0
fi

echo "[INFO] Deleting package ${package_version} (ID: ${package_id})..."
delete_url="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/${package_id}"
delete_response=$(curl -sk -X DELETE -w "\n%{http_code}" --header "JOB-TOKEN: ${CI_JOB_TOKEN}" "${delete_url}")
delete_status=$(echo "${delete_response}" | tail -1)

if [ "${delete_status}" != "204" ] && [ "${delete_status}" != "200" ]; then
    echo "[ERROR] Delete failed for package ${package_version}: HTTP ${delete_status}" >&2
    echo "[DEBUG] Response: $(echo "${delete_response}" | sed '$d')" >&2
    exit 1
fi

echo "[SUCCESS] Package version ${package_version} deleted."

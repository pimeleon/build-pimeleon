#!/bin/sh
set -eu

# Check whether a Pimeleon package version already exists in the GitLab package registry.
# Exit codes:
#   0 => package exists
#   1 => package does not exist
#   2 => registry query failed

package_version="${1:-}"

[ -n "${package_version}" ] || { echo "[ERROR] package version is required" >&2; exit 2; }
[ -n "${CI_API_V4_URL:-}" ] || { echo "[ERROR] CI_API_V4_URL is not set" >&2; exit 2; }
[ -n "${CI_PROJECT_ID:-}" ] || { echo "[ERROR] CI_PROJECT_ID is not set" >&2; exit 2; }
[ -n "${CI_JOB_TOKEN:-}" ] || { echo "[ERROR] CI_JOB_TOKEN is not set" >&2; exit 2; }

registry_url="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages?package_name=pimeleon&package_version=${package_version}"
http_response=$(curl -sk -w "\n%{http_code}" --header "JOB-TOKEN: ${CI_JOB_TOKEN}" "${registry_url}")
status=$(echo "${http_response}" | tail -1)
result=$(echo "${http_response}" | sed '$d')

if [ "${status}" != "200" ]; then
    echo "[ERROR] Registry query failed for ${package_version}: HTTP ${status}" >&2
    echo "[DEBUG] URL: ${registry_url}" >&2
    echo "[DEBUG] Response: ${result}" >&2
    exit 2
fi

if echo "${result}" | grep -q '"id":'; then
    exit 0
fi

exit 1

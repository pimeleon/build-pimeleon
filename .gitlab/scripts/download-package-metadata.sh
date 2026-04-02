#!/bin/sh
set -eu

# Download the metadata JSON artifact for an existing Pimeleon package version.
# Usage: download-package-metadata.sh <package_version> <output_path>
#
# Exit codes:
#   0 => metadata downloaded
#   3 => package exists but has no metadata artifact (legacy package)

package_version="${1:-}"
output_path="${2:-}"

[ -n "${package_version}" ] || { echo "[ERROR] package version is required" >&2; exit 1; }
[ -n "${output_path}" ] || { echo "[ERROR] output path is required" >&2; exit 1; }
[ -n "${CI_API_V4_URL:-}" ] || { echo "[ERROR] CI_API_V4_URL is not set" >&2; exit 1; }
[ -n "${CI_PROJECT_ID:-}" ] || { echo "[ERROR] CI_PROJECT_ID is not set" >&2; exit 1; }
[ -n "${CI_JOB_TOKEN:-}" ] || { echo "[ERROR] CI_JOB_TOKEN is not set" >&2; exit 1; }

packages_url="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages?package_name=pimeleon&package_version=${package_version}"
packages_response=$(curl -sk -w "\n%{http_code}" --header "JOB-TOKEN: ${CI_JOB_TOKEN}" "${packages_url}")
packages_status=$(echo "${packages_response}" | tail -1)
packages_result=$(echo "${packages_response}" | sed '$d')

if [ "${packages_status}" != "200" ]; then
    echo "[ERROR] Package lookup failed for ${package_version}: HTTP ${packages_status}" >&2
    echo "[DEBUG] URL: ${packages_url}" >&2
    echo "[DEBUG] Response: ${packages_result}" >&2
    exit 1
fi

package_id=$(printf "%s" "${packages_result}" | grep -o '"id":[[:space:]]*[0-9]\+' | head -1 | grep -o '[0-9]\+' || true)
[ -n "${package_id}" ] || { echo "[ERROR] No package id found for ${package_version}" >&2; exit 1; }

files_url="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/${package_id}/package_files"
files_response=$(curl -sk -w "\n%{http_code}" --header "JOB-TOKEN: ${CI_JOB_TOKEN}" "${files_url}")
files_status=$(echo "${files_response}" | tail -1)
files_result=$(echo "${files_response}" | sed '$d')

if [ "${files_status}" != "200" ]; then
    echo "[ERROR] Package file lookup failed for ${package_version}: HTTP ${files_status}" >&2
    echo "[DEBUG] URL: ${files_url}" >&2
    echo "[DEBUG] Response: ${files_result}" >&2
    exit 1
fi

file_name=$(printf "%s" "${files_result}" | grep -o '"file_name":"[^"]*\.metadata\.json"' | head -1 | sed 's/.*"file_name":"//; s/"$//' || true)
if [ -z "${file_name}" ]; then
    echo "[WARN] No .metadata.json file found for ${package_version}" >&2
    exit 3
fi

mkdir -p "$(dirname "${output_path}")"
download_url="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/pimeleon/${package_version}/${file_name}"

echo "[INFO] Downloading existing metadata artifact ${file_name}"
curl -sk --fail --header "JOB-TOKEN: ${CI_JOB_TOKEN}" -o "${output_path}" "${download_url}"

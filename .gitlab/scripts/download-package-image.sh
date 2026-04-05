#!/bin/sh
set -eu

# Download the compressed image artifact for an existing Pimeleon package version.
# Usage: download-package-image.sh <package_version> <output_dir>

SCRIPT_DIR="$(dirname "$0")"
. "${SCRIPT_DIR}/../../shared/scripts/lib-api.sh"

package_version="${1:-}"
output_dir="${2:-output}"

[ -n "${package_version}" ] || { echo "[ERROR] package version is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq is required" >&2; exit 1; }

package_id=$(gitlab_package_id "${package_version}") || exit 1

files_body=$(gitlab_api_get "/projects/${GITLAB_PROJECT}/packages/${package_id}/package_files") || exit 1

file_name=$(printf '%s' "${files_body}" | \
    jq -r '[.[] | .file_name | select(endswith(".img.xz"))] | first // empty' 2>/dev/null)
[ -n "${file_name}" ] || { echo "[ERROR] No .img.xz file found for ${package_version}" >&2; exit 1; }

mkdir -p "${output_dir}"
download_url="${GITLAB_API_URL}/projects/${GITLAB_PROJECT}/packages/generic/pimeleon/${package_version}/${file_name}"

echo "[INFO] Downloading existing image artifact ${file_name}"
gitlab_download "${download_url}" "${output_dir}/${file_name}"

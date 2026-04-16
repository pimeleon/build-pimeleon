#!/bin/sh
set -eu

# Download the metadata JSON artifact for an existing Pimeleon package version.
# Usage: download-package-metadata.sh <package_version> <output_path>
#
# Exit codes:
#   0 => metadata downloaded
#   3 => package exists but has no metadata artifact (legacy package)

SCRIPT_DIR="$(dirname "$0")"
. "${SCRIPT_DIR}/../../shared/scripts/lib-api.sh"

package_version="${1:-}"
output_path="${2:-}"

[ -n "${package_version}" ] || { echo "[ERROR] package version is required" >&2; exit 1; }
[ -n "${output_path}" ] || { echo "[ERROR] output path is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq is required" >&2; exit 1; }

package_id=$(gitlab_package_id "${package_version}") || exit 1

files_body=$(gitlab_api_get "/projects/${GITLAB_PROJECT}/packages/${package_id}/package_files") || exit 1

file_name=$(printf '%s' "${files_body}" | \
    jq -r '[.[] | .file_name | select(endswith(".metadata.json"))] | first // empty' 2>/dev/null)
if [ -z "${file_name}" ]; then
    echo "[WARN] No .metadata.json file found for ${package_version}" >&2
    exit 3
fi

mkdir -p "$(dirname "${output_path}")"
download_url="${GITLAB_API_URL}/projects/${GITLAB_PROJECT}/packages/generic/pimeleon/${package_version}/${file_name}"

echo "[INFO] Downloading existing metadata artifact ${file_name}"
gitlab_download "${download_url}" "${output_path}"

#!/bin/sh
set -eu

# Provide artifacts either by validating the local build output,
# or by downloading existing artifacts from the GitLab Package Registry.

mkdir -p output

# Check if a fresh build actually produced an image in this pipeline
if [ -n "$(ls -A output/*.img 2>/dev/null)" ]; then
  echo "Fresh build detected in output/ directory. Proceeding with artifact upload."
  exit 0
fi

# No fresh build found, attempt to download existing version
if [ "${IMAGE_EXISTS:-false}" = "true" ]; then
  echo "No fresh build found, but version exists in registry. Downloading artifacts..."

  if [ -z "${PACKAGE_VERSION:-}" ]; then
    echo "ERROR: PACKAGE_VERSION is missing from environment"
    exit 1
  fi

  echo "Fetching metadata for pimeleon/${PACKAGE_VERSION}..."
  RES=$(curl -s --header "JOB-TOKEN: $CI_JOB_TOKEN" "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages?package_name=pimeleon&package_version=${PACKAGE_VERSION}")

  if command -v jq >/dev/null 2>&1; then
    PKG_ID=$(echo "$RES" | jq -r '.[0].id // empty')
  else
    PKG_ID=$(echo "$RES" | grep -o '"id":[0-9]*' | head -1 | awk -F':' '{print $2}')
  fi

  if [ -z "$PKG_ID" ]; then
    echo "ERROR: Package not found in registry!"
    exit 1
  fi

  echo "Found package ID: ${PKG_ID}. Fetching files list..."
  FILES=$(curl -s --header "JOB-TOKEN: $CI_JOB_TOKEN" "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/${PKG_ID}/package_files")

  if command -v jq >/dev/null 2>&1; then
    echo "$FILES" | jq -r '.[].file_name' > /tmp/filenames.txt
  else
    echo "$FILES" | grep -o '"file_name":"[^"]*"' | awk -F'"' '{print $4}' > /tmp/filenames.txt
  fi

  while IFS= read -r filename; do
    [ -z "$filename" ] && continue
    echo "Downloading ${filename}..."
    curl -s -L --header "JOB-TOKEN: $CI_JOB_TOKEN" "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/pimeleon/${PACKAGE_VERSION}/${filename}" -o "output/${filename}"
  done < /tmp/filenames.txt

  rm -f /tmp/filenames.txt
  echo "Downloaded artifacts list:"
  ls -lh output/
else
  echo "ERROR: No fresh build found and IMAGE_EXISTS is false. Build likely failed or was skipped incorrectly."
  exit 1
fi

#!/bin/sh
set -eu

# Upload Pimeleon image artifacts to the GitLab Generic Packages registry.
# If the image already exists (IMAGE_EXISTS=true), it skips the network operations.
#
# Inputs: IMAGE_EXISTS, PACKAGE_VERSION, TARGET_PLATFORM, CI_JOB_TOKEN, CI_API_V4_URL, CI_PROJECT_ID

IMAGE_EXISTS="${IMAGE_EXISTS:-false}"

if [ "$IMAGE_EXISTS" = "true" ]; then
  echo "[INFO] Image version '${PACKAGE_VERSION}' confirmed in registry."
  echo "[INFO] Skipping upload operations to optimize network usage."
  mkdir -p output
  echo "Registry: ${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages" > output/registry_link.txt
  exit 0
fi

echo "[INFO] Image missing from registry. Starting upload of local artifacts..."
ls -lh output/ 2>/dev/null || true

if [ -z "$(ls -A output/*.img.xz 2>/dev/null)" ]; then
  echo "[ERROR] No .img.xz artifacts found in output/. Build likely failed."
  exit 1
fi

# Upload logic
for file in output/pimeleon-*.img.xz output/*.sha256; do
  if [ -f "$file" ]; then
    echo "[INFO] Uploading $(basename "$file")..."
    curl --header "JOB-TOKEN: $CI_JOB_TOKEN" \
      --upload-file "$file" \
      "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/pimeleon/${PACKAGE_VERSION}/$(basename "$file")"
  fi
done

echo "[SUCCESS] All artifacts uploaded to registry."

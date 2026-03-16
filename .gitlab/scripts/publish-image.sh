#!/bin/sh
set -eu
# Upload Pimeleon image artifacts to the GitLab Generic Packages registry.
#
# Inputs (CI environment):
#   TARGET_PLATFORM, CI_JOB_TOKEN, CI_API_V4_URL, CI_PROJECT_ID

SCRIPTS_DIR="./shared/scripts"
[ ! -f "./scripts/build.sh" ] || SCRIPTS_DIR="./scripts"
chmod +x "${SCRIPTS_DIR}/get-next-version.sh"
VERSION=$("${SCRIPTS_DIR}/get-next-version.sh" "${TARGET_PLATFORM}")
echo "Publishing version ${VERSION} for ${TARGET_PLATFORM}"

cd output
for file in pimeleon-*.img.xz pimeleon-*.tar.gz; do
  if [ -f "$file" ]; then
    curl --header "JOB-TOKEN: $CI_JOB_TOKEN" \
      --upload-file "$file" \
      "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/pimeleon/${TARGET_PLATFORM}-v${VERSION}/$(basename "$file")"
  fi
done

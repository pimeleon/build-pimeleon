#!/bin/sh
set -eu
# Dry-run validation of Pimeleon R2 deployment.
# Actual R2 upload is handled by GitHub Actions (triggered after this job).
#
# Inputs (CI environment):
#   TARGET_PLATFORM, R2_BUCKET, R2_ENDPOINT

SCRIPTS_DIR="./shared/scripts"
[ ! -f "./scripts/build.sh" ] || SCRIPTS_DIR="./scripts"

# Verify required R2 variables
if [ -z "${R2_BUCKET:-}" ] || [ -z "${R2_ENDPOINT:-}" ]; then
  echo "Warning: R2_BUCKET or R2_ENDPOINT not set."
  exit 1
fi

apk add --no-cache git >/dev/null 2>&1 || true

chmod +x "${SCRIPTS_DIR}/get-next-version.sh"
VERSION=$("${SCRIPTS_DIR}/get-next-version.sh" "${TARGET_PLATFORM}")
UPLOAD_PREFIX="${TARGET_PLATFORM}/v${VERSION}"

echo "=== R2 Deployment Dry Run ==="
echo "Bucket:    s3://${R2_BUCKET}"
echo "Endpoint:  ${R2_ENDPOINT}"
echo "Prefix:    ${UPLOAD_PREFIX}"
echo ""

FILE_COUNT=0
cd output
for file in pimeleon-*.img.xz pimeleon-*.img.metadata.json; do
  [ -f "$file" ] || continue
  FILE_SIZE=$(ls -lh "$file" | awk '{print $5}')
  echo "[DRY RUN] Would upload: $file (${FILE_SIZE}) -> s3://${R2_BUCKET}/${UPLOAD_PREFIX}/$(basename "$file")"
  FILE_COUNT=$((FILE_COUNT + 1))
done

if [ "$FILE_COUNT" -eq 0 ]; then
  echo "Error: No artifacts found matching pimeleon-*.img.xz"
  exit 1
fi

echo ""
echo "Validated ${FILE_COUNT} file(s) for R2 deployment."
echo "Actual upload will be performed by GitHub Actions."

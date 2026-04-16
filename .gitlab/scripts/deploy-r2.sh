#!/bin/sh
set -eu

# Install dependencies needed for version calculation and R2 uploads
apk add --no-cache git aws-cli curl >/dev/null 2>&1 || true

# Deploy Pimeleon image artifacts to Cloudflare R2 via S3-compatible API.
#
# Inputs (CI environment):
#   TARGET_PLATFORM, PIMELEON_VERSION, R2_BUCKET, R2_ENDPOINT
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION (set by job)

[ -n "${PIMELEON_VERSION:-}" ] || {
    echo "[ERROR] PIMELEON_VERSION is not set. Run .gitlab/scripts/detect-platform.sh first."
    exit 1
}

VERSION="${PIMELEON_VERSION}"
PACKAGE_VERSION="${TARGET_PLATFORM}-v${VERSION}"
UPLOAD_PREFIX="${TARGET_PLATFORM}/v${VERSION}"
echo "Deploying to R2: s3://${R2_BUCKET}/${UPLOAD_PREFIX}/"

# Check for artifacts and handle skip case
if [ ! -d "output" ] || [ -z "$(ls -A output/pimeleon-*.img.xz 2>/dev/null)" ]; then
    if sh .gitlab/scripts/check-package-exists.sh "${PACKAGE_VERSION}"; then
        echo "[INFO] Package ${PACKAGE_VERSION} already exists in the registry and no fresh artifacts were produced. Skipping R2 deployment."
        exit 0
    fi

    echo "[ERROR] No artifacts found in output/ and package ${PACKAGE_VERSION} does not exist in registry."
    exit 1
fi

cd output
for file in pimeleon-*.img.xz pimeleon-*.img.metadata.json; do
    [ -f "$file" ] || continue
    echo "Uploading $file..."
    aws s3 cp "$file" "s3://${R2_BUCKET}/${UPLOAD_PREFIX}/$(basename "$file")" \
        --endpoint-url "${R2_ENDPOINT}"
done

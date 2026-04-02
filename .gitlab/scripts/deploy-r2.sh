#!/bin/sh
set -eu

# Install dependencies needed for version calculation and R2 uploads
apk add --no-cache git aws-cli >/dev/null 2>&1 || true

# Deploy Pimeleon image artifacts to Cloudflare R2 via S3-compatible API.
#
# Inputs (CI environment):
#   TARGET_PLATFORM, R2_BUCKET, R2_ENDPOINT
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION (set by job)

VERSION=$(.gitlab/scripts/resolve-version.sh base "${TARGET_PLATFORM}")
UPLOAD_PREFIX="${TARGET_PLATFORM}/v${VERSION}"
echo "Deploying to R2: s3://${R2_BUCKET}/${UPLOAD_PREFIX}/"

cd output
for file in pimeleon-*.img.xz pimeleon-*.img.metadata.json; do
    [ -f "$file" ] || continue
    echo "Uploading $file..."
    aws s3 cp "$file" "s3://${R2_BUCKET}/${UPLOAD_PREFIX}/$(basename "$file")" \
        --endpoint-url "${R2_ENDPOINT}" \
        --no-progress
done

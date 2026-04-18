#!/bin/sh
set -eu

# Install dependencies needed for version calculation and R2 uploads
apk add --no-cache git aws-cli curl >/dev/null 2>&1 || true

# Deploy Pimeleon image artifacts to Cloudflare R2 via S3-compatible API.
#
# Inputs (CI environment):
#   TARGET_PLATFORM, R2_BUCKET, R2_ENDPOINT
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION (set by job)

# Resolve version and artifacts.
# Fresh build path: artifacts are in output/ — version is the next calculated version.
# Registry fallback path: no fresh build (release-push pipeline after MR merge) — query the
# registry for the latest actually-published package version for this platform instead of
# re-running get-next-version.sh, which would return the bumped-again next version.
if [ ! -d "output" ] || [ -z "$(ls -A output/pimeleon-*.img.xz 2>/dev/null)" ]; then
    _resp=$(curl -sk -w "\n%{http_code}" \
        --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
        "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages?package_name=pimeleon&sort=desc&order_by=created_at&per_page=50")
    _status=$(printf '%s' "$_resp" | tail -1)
    _body=$(printf '%s' "$_resp" | sed '$d')

    if [ "$_status" != "200" ]; then
        echo "[ERROR] Failed to query package registry: HTTP ${_status}" >&2
        exit 1
    fi

    PACKAGE_VERSION=$(printf '%s' "$_body" \
        | grep -oE "\"version\"[[:space:]]*:[[:space:]]*\"${TARGET_PLATFORM}-v[^\"]*\"" \
        | head -1 \
        | grep -oE "${TARGET_PLATFORM}-v[^\"]*")

    if [ -z "${PACKAGE_VERSION:-}" ]; then
        echo "[ERROR] No published package found in registry for platform ${TARGET_PLATFORM}" >&2
        exit 1
    fi

    VERSION=$(printf '%s' "$PACKAGE_VERSION" | sed "s/^${TARGET_PLATFORM}-v//")
    echo "[INFO] No fresh artifacts — deploying latest published package: ${PACKAGE_VERSION}"
    sh .gitlab/scripts/download-package-image.sh "${PACKAGE_VERSION}" output
    sh .gitlab/scripts/download-package-metadata.sh "${PACKAGE_VERSION}" "output/pimeleon-${PACKAGE_VERSION}.img.metadata.json" || true
else
    VERSION=$(sh .gitlab/scripts/resolve-version.sh base "${TARGET_PLATFORM}")
    PACKAGE_VERSION=$(sh .gitlab/scripts/resolve-version.sh package "${TARGET_PLATFORM}")
fi

UPLOAD_PREFIX="${TARGET_PLATFORM}/v${VERSION}"
echo "Deploying to R2: s3://${R2_BUCKET}/${UPLOAD_PREFIX}/"

cd output
for file in pimeleon-*.img.xz pimeleon-*.img.metadata.json; do
    [ -f "$file" ] || continue
    echo "Uploading $file..."
    aws s3 cp "$file" "s3://${R2_BUCKET}/${UPLOAD_PREFIX}/$(basename "$file")" \
        --endpoint-url "${R2_ENDPOINT}"
done

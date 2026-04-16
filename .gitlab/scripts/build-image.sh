#!/bin/sh
set -eu

# Build a Pimeleon image inside a privileged Docker container.
# Detects directories, computes version, manages container lifecycle,
# and extracts build artifacts.
#
# Inputs (CI environment):
#   TARGET_PLATFORM, PIMELEON_PROFILE, BUILD_IMAGE, CI_PROJECT_DIR,
#   CI_COMMIT_SHORT_SHA, CI_COMMIT_TAG, CI_COMMIT_BRANCH, CI_PIPELINE_SOURCE,
#   CI_MERGE_REQUEST_TARGET_BRANCH_NAME, APT_PROXY, PIMELEON_UI_BRANCH,
#   PIMELEON_UI_BUILD_TOKEN,
#   PIMELEON_APPS_SOURCE, PIMELEON_APPS_PROJECT_ID, PIMELEON_APPS_READ_TOKEN,
#   PIMELEON_APPS_GITHUB_TOKEN

apk add --no-cache curl git jq >/dev/null 2>&1 || true

[ -n "${TARGET_PLATFORM}" ]   || { echo "[ERROR] TARGET_PLATFORM is not set"; exit 1; }
[ -n "${PIMELEON_PROFILE}" ] || { echo "[ERROR] PIMELEON_PROFILE is not set"; exit 1; }
echo "Building Pimeleon image for ${TARGET_PLATFORM} (Profile: ${PIMELEON_PROFILE})..."

mkdir -p output cache

# Detect directories — shared baseline, branch-local overrides
# In the monorepo refactor, core logic lives in shared/
ANSIBLE_DIR="./shared/ansible"
CONFIGS_DIR="./shared/configs"
SCRIPTS_DIR="./shared/scripts"

# Support branch-specific overrides in root if files exist
[ ! -f "./ansible/playbooks/main.yml" ] || ANSIBLE_DIR="./ansible"
[ ! -d "./configs/network" ]            || CONFIGS_DIR="./configs"
[ ! -f "./scripts/build.sh" ]           || SCRIPTS_DIR="./scripts"

echo "Using ansible=${ANSIBLE_DIR} configs=${CONFIGS_DIR} scripts=${SCRIPTS_DIR}"

# Use the pipeline-resolved version from setup:platform.
[ -n "${PIMELEON_VERSION:-}" ] || {
    echo "[ERROR] PIMELEON_VERSION is not set. Run .gitlab/scripts/detect-platform.sh first."
    exit 1
}

PACKAGE_VERSION="${TARGET_PLATFORM}-v${PIMELEON_VERSION}"
BUILDER_IMAGE_DIGEST=$(sh .gitlab/scripts/resolve-builder-image-digest.sh "${BUILD_IMAGE}")
echo "[INFO] Building version: ${PIMELEON_VERSION}"
echo "[INFO] Package version: ${PACKAGE_VERSION}"
echo "[INFO] Builder image digest: ${BUILDER_IMAGE_DIGEST}"

echo "[INFO] Checking registry for existing image package..."
if sh .gitlab/scripts/check-package-exists.sh "${PACKAGE_VERSION}"; then
    metadata_file="$(mktemp)"
    trap 'rm -f "${metadata_file}"' EXIT
    if sh .gitlab/scripts/download-package-metadata.sh "${PACKAGE_VERSION}" "${metadata_file}"; then
        existing_builder_digest=$(grep -o '"builder_image_digest":[[:space:]]*"[^"]*"' "${metadata_file}" | head -1 | sed 's/.*"builder_image_digest":[[:space:]]*"//; s/"$//' || true)

        if [ -n "${existing_builder_digest}" ] && [ "${existing_builder_digest}" = "${BUILDER_IMAGE_DIGEST}" ]; then
            echo "[INFO] Package ${PACKAGE_VERSION} already exists and matches builder digest ${BUILDER_IMAGE_DIGEST}. Skipping image build."
            mkdir -p output
            exit 0
        fi

        echo "[INFO] Package ${PACKAGE_VERSION} exists but was built with a different builder image."
        echo "[INFO] Existing digest: ${existing_builder_digest:-unknown}"
        echo "[INFO] Current digest:  ${BUILDER_IMAGE_DIGEST}"
    else
        status=$?
        if [ "${status}" -eq 3 ]; then
            echo "[INFO] Package ${PACKAGE_VERSION} exists but has no metadata artifact. Rebuilding to refresh package metadata."
        else
            exit "${status}"
        fi
    fi
else
    status=$?
    if [ "${status}" -ne 1 ]; then
        exit "${status}"
    fi
fi

# Create and start build container
# $BUILD_IMAGE is expected to be provided by the CI environment
echo "[INFO] Using builder image: ${BUILD_IMAGE}"
CONTAINER_ID=$(docker create \
        --privileged \
        -v /dev:/dev:rw \
        -v "${CI_PROJECT_DIR}/cache":/cache \
        -e CI=true \
        -e WORKSPACE_DIR=/workspace \
        -e CACHE_DIR=/cache \
        -e OUTPUT_DIR=/output \
        -e TARGET_PLATFORM="${TARGET_PLATFORM}" \
        -e PIMELEON_VERSION="${PIMELEON_VERSION}" \
        -e PIMELEON_PROFILE="${PIMELEON_PROFILE}" \
        -e BUILDER_IMAGE_REF="${BUILD_IMAGE}" \
        -e BUILDER_IMAGE_DIGEST="${BUILDER_IMAGE_DIGEST}" \
                -e APT_PROXY="${APT_PROXY:-}" \
        -e PIMELEON_UI_BUILD_TOKEN="${PIMELEON_UI_BUILD_TOKEN:-}" \
        -e PIMELEON_APPS_SOURCE="${PIMELEON_APPS_SOURCE}" \
        -e PIMELEON_APPS_PROJECT_ID="${PIMELEON_APPS_PROJECT_ID:-}" \
        -e PIMELEON_APPS_READ_TOKEN="${PIMELEON_APPS_READ_TOKEN:-}" \
        -e PIMELEON_APPS_GITHUB_TOKEN="${PIMELEON_APPS_GITHUB_TOKEN:-}" \
    "${BUILD_IMAGE}")

# Persist container ID for after_script cleanup on cancel/timeout
echo "$CONTAINER_ID" > .build_container_id

docker cp "${SCRIPTS_DIR}/." "$CONTAINER_ID":/scripts/
docker cp "${CONFIGS_DIR}/." "$CONTAINER_ID":/configs/
docker cp "${ANSIBLE_DIR}/." "$CONTAINER_ID":/ansible/
docker start -a "$CONTAINER_ID"

EXIT_CODE=$(docker inspect "$CONTAINER_ID" --format='{{.State.ExitCode}}')
echo "Container exit code: ${EXIT_CODE}"
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "Error: Build container failed with exit code ${EXIT_CODE}"
    docker cp "$CONTAINER_ID":/output/. output/ || true
    docker rm -f "$CONTAINER_ID" || true
    rm -f .build_container_id
    exit 1
fi

echo "Extracting artifacts from container..."
docker cp "$CONTAINER_ID":/output/. output/
docker rm -f "$CONTAINER_ID" || true
rm -f .build_container_id

echo "Build output:"
ls -la output/

# Ensure artifacts were actually produced
if [ -z "$(ls -A output/*.img 2>/dev/null)" ]; then
    echo "Error: No image artifacts found in output/"
    exit 1
fi

chown -R "$(id -u):$(id -g)" output/ || true

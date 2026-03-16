#!/bin/sh
set -eu

# Build a Pimeleon image inside a privileged Docker container.
# Detects directories, computes version, manages container lifecycle,
# and extracts build artifacts.
#
# Inputs (CI environment):
#   TARGET_PLATFORM, PIMELEON_PROFILE, BUILD_IMAGE, CI_PROJECT_DIR,
#   CI_COMMIT_SHORT_SHA, APT_PROXY, PIMELEON_UI_BUILD_TOKEN,
#   PIMELEON_APPS_SOURCE, PIMELEON_APPS_PROJECT_ID, PIMELEON_APPS_READ_TOKEN,
#   PIMELEON_APPS_GITHUB_TOKEN

[ -n "${TARGET_PLATFORM:-}" ]   || { echo "[ERROR] TARGET_PLATFORM is not set"; exit 1; }
[ -n "${PIMELEON_PROFILE:-}" ] || { echo "[ERROR] PIMELEON_PROFILE is not set"; exit 1; }
echo "Building Pimeleon image for ${TARGET_PLATFORM} (Profile: ${PIMELEON_PROFILE})..."

mkdir -p output cache

# Detect directories — shared baseline, branch-local overrides
ANSIBLE_DIR="./shared/ansible"
CONFIGS_DIR="./shared/configs"
SCRIPTS_DIR="./shared/scripts"
[ ! -f "./ansible/playbooks/main.yml" ] || ANSIBLE_DIR="./ansible"
[ ! -d "./configs/network" ]            || CONFIGS_DIR="./configs"
[ ! -f "./scripts/build.sh" ]           || SCRIPTS_DIR="./scripts"
echo "Using ansible=${ANSIBLE_DIR} configs=${CONFIGS_DIR} scripts=${SCRIPTS_DIR}"

# Compute version
chmod +x "${SCRIPTS_DIR}/get-next-version.sh"
BASE_VERSION=$("${SCRIPTS_DIR}/get-next-version.sh" "${TARGET_PLATFORM}")
PIMELEON_VERSION="${BASE_VERSION}-${CI_COMMIT_SHORT_SHA}"
echo "Building version: ${PIMELEON_VERSION}"

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

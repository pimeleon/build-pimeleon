#!/bin/sh
set -eu
# Build a Pimeleon image inside a privileged Docker container.
# Detects directories, computes version, manages container lifecycle,
# and extracts build artifacts.
#
# Inputs (CI environment):
#   TARGET_PLATFORM, PIMELEON_PROFILE, BUILD_IMAGE, CI_PROJECT_DIR,
#   CI_COMMIT_SHORT_SHA, APT_PROXY, PIMELEON_UI_BUILD_TOKEN,
#   PIMELEON_APPS_GITHUB_TOKEN

TARGET_PLATFORM="${TARGET_PLATFORM:-rpi3-bookworm}"
PIMELEON_PROFILE="${PIMELEON_PROFILE:-production}"
echo "Building Pimeleon image for ${TARGET_PLATFORM} (Profile: ${PIMELEON_PROFILE})..."

ANSIBLE_DIR="./shared/ansible"
CONFIGS_DIR="./shared/configs"
SCRIPTS_DIR="./shared/scripts"

# Use local directories if available (development)
[ ! -d "./ansible" ] || ANSIBLE_DIR="./ansible"
[ ! -d "./configs" ] || CONFIGS_DIR="./configs"
[ ! -d "./scripts" ] || SCRIPTS_DIR="./scripts"

echo "Using ansible=${ANSIBLE_DIR} configs=${CONFIGS_DIR} scripts=${SCRIPTS_DIR}"

# Compute version
chmod +x "${SCRIPTS_DIR}/get-next-version.sh"
BASE_VERSION=$("${SCRIPTS_DIR}/get-next-version.sh" "${TARGET_PLATFORM}")
PIMELEON_VERSION="${BASE_VERSION}"
echo "Building version: ${PIMELEON_VERSION}"

# Create and start build container
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
  -e PIMELEON_APPS_GITHUB_TOKEN="${PIMELEON_APPS_GITHUB_TOKEN:-}" \
  --network host \
  "$BUILD_IMAGE")

echo "Created container: ${CONTAINER_ID}"

# Extract scripts/configs to a temporary location for the container to use
docker cp "${ANSIBLE_DIR}" "${CONTAINER_ID}:/ansible"
docker cp "${CONFIGS_DIR}" "${CONTAINER_ID}:/configs"
docker cp "${SCRIPTS_DIR}" "${CONTAINER_ID}:/scripts"

# Run the build script inside the container
docker start -a "${CONTAINER_ID}"

# Extract artifacts
mkdir -p output
docker cp "${CONTAINER_ID}:/output/." output/

# Cleanup
docker rm "${CONTAINER_ID}"

echo "Build output:"
ls -la output/

# Ensure artifacts were actually produced
if [ -z "$(ls -A output/*.img 2>/dev/null)" ]; then
  echo "Error: No image artifacts found in output/"
  exit 1
fi

chown -R "$(id -u):$(id -g)" output/ || true

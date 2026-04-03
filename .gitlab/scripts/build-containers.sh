#!/bin/sh
set -eu
# Build and push builder/tester Docker images to the CI registry.
#
# Inputs (CI environment):
#   CI_REGISTRY_IMAGE, BUILD_IMAGE, TEST_IMAGE, APT_PROXY, CI, PIMELEON_PROFILE
# Re-evaluate BUILD_IMAGE to bypass GitLab CI rules variables bug
export BUILD_IMAGE="${CI_REGISTRY_IMAGE}/${BUILD_IMAGE_NAME}:${BUILD_IMAGE_TAG}"
export TEST_IMAGE="${CI_REGISTRY_IMAGE}/${TEST_IMAGE_NAME}:${TEST_IMAGE_TAG}"

# Prioritize local Dockerfiles if they exist in the branch root
BUILDER_DF="./containers/builder/Dockerfile"
TESTER_DF="./containers/tester/Dockerfile"
[ -f "$BUILDER_DF" ] || BUILDER_DF="./shared/containers/builder/Dockerfile"
[ -f "$TESTER_DF" ]  || TESTER_DF="./shared/containers/tester/Dockerfile"

echo "Using builder Dockerfile: ${BUILDER_DF}"
echo "Using tester Dockerfile: ${TESTER_DF}"

# adblock2privoxy base image is managed by the sync:ab2p job in .pre stage.
# We just ensure it's available locally.
AB2P_IMAGE="${CI_REGISTRY_IMAGE}/adblock2privoxy:latest"
if ! docker image inspect "${AB2P_IMAGE}" >/dev/null 2>&1; then
    echo "adblock2privoxy image not found locally, pulling from registry..."
    docker pull "${AB2P_IMAGE}"
fi

# Build builder image
echo "Building builder image..."
docker build \
    --cache-from "${CI_REGISTRY_IMAGE}/builder:latest" \
    --build-arg AB2P_IMAGE="${AB2P_IMAGE}" \
    --build-arg APT_PROXY="${APT_PROXY:-}" \
    --build-arg CI="${CI:-}" \
    --build-arg PIMELEON_PROFILE="${PIMELEON_PROFILE}" \
    -t "$BUILD_IMAGE" -t "${CI_REGISTRY_IMAGE}/builder:latest" \
    -f "$BUILDER_DF" .

# Build tester image
echo "Building tester image..."
docker build \
    --cache-from "${CI_REGISTRY_IMAGE}/tester:latest" \
    --build-arg APT_PROXY="${APT_PROXY}" \
    --build-arg CI="${CI:-}" \
    --build-arg PIMELEON_PROFILE="${PIMELEON_PROFILE}" \
    -t "$TEST_IMAGE" -t "${CI_REGISTRY_IMAGE}/tester:latest" \
    -f "$TESTER_DF" "$(dirname "$TESTER_DF")"

docker push --quiet "$BUILD_IMAGE"
docker push --quiet "${CI_REGISTRY_IMAGE}/builder:latest"
docker push --quiet "$TEST_IMAGE"
docker push --quiet "${CI_REGISTRY_IMAGE}/tester:latest"

echo "Builder and tester images built and pushed successfully"

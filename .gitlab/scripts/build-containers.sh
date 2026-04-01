#!/bin/sh
set -eu
# Build and push builder/tester Docker images to the CI registry.
# Uses BuildKit registry cache for optimal layer reuse across jobs/branches.
#
# Inputs (CI environment):
#   CI_REGISTRY_IMAGE, BUILD_IMAGE, TEST_IMAGE, APT_PROXY, CI, PIMELEON_PROFILE,
#   CACHE_IMAGE, BUILDKIT_INLINE_CACHE

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

# Create BuildKit builder with docker-container driver (required for registry cache backend)
docker buildx create --use --driver docker-container

# Ensure adblock2privoxy base image exists in the registry (build once, reuse forever)
AB2P_IMAGE="${CI_REGISTRY_IMAGE}/adblock2privoxy:latest"
AB2P_DF="./shared/containers/builder/Dockerfile.ab2p"
[ -f "./containers/builder/Dockerfile.ab2p" ] && AB2P_DF="./containers/builder/Dockerfile.ab2p"

if docker manifest inspect "${AB2P_IMAGE}" >/dev/null 2>&1; then
    echo "adblock2privoxy image found in registry, skipping build"
else
    echo "adblock2privoxy image not found — building and pushing to registry..."
    docker buildx build \
        --cache-from type=registry,ref="${CACHE_IMAGE}:ab2p-main" \
        --cache-to type=registry,ref="${CACHE_IMAGE}:ab2p-main",mode=max \
        -t "${AB2P_IMAGE}" \
        --push \
        -f "$AB2P_DF" "$(dirname "$AB2P_DF")"
    echo "adblock2privoxy image pushed: ${AB2P_IMAGE}"
fi

# Build builder image with BuildKit registry cache
echo "Building builder image..."
docker buildx build \
    --cache-from type=registry,ref="${CACHE_IMAGE}:builder-${CI_COMMIT_REF_SLUG}" \
    --cache-from type=registry,ref="${CACHE_IMAGE}:builder-main" \
    --cache-to type=registry,ref="${CACHE_IMAGE}:builder-${CI_COMMIT_REF_SLUG}",mode=max \
    --build-arg AB2P_IMAGE="${AB2P_IMAGE}" \
    --build-arg APT_PROXY="${APT_PROXY:-}" \
    --build-arg CI="${CI:-}" \
    --build-arg PIMELEON_PROFILE="${PIMELEON_PROFILE:-}" \
    -t "$BUILD_IMAGE" -t "${CI_REGISTRY_IMAGE}/builder:latest" \
    --push \
    -f "$BUILDER_DF" .

# Build tester image with BuildKit registry cache
echo "Building tester image..."
docker buildx build \
    --cache-from type=registry,ref="${CACHE_IMAGE}:tester-${CI_COMMIT_REF_SLUG}" \
    --cache-from type=registry,ref="${CACHE_IMAGE}:tester-main" \
    --cache-to type=registry,ref="${CACHE_IMAGE}:tester-${CI_COMMIT_REF_SLUG}",mode=max \
    --build-arg APT_PROXY="${APT_PROXY:-}" \
    --build-arg CI="${CI:-}" \
    --build-arg PIMELEON_PROFILE="${PIMELEON_PROFILE:-}" \
    -t "$TEST_IMAGE" -t "${CI_REGISTRY_IMAGE}/tester:latest" \
    --push \
    -f "$TESTER_DF" "$(dirname "$TESTER_DF")"

echo "Builder and tester images built and pushed successfully"

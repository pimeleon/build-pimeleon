#!/bin/sh
set -eu
# Build and push builder/tester Docker images to the CI registry.
# Uses BuildKit registry cache for optimal layer reuse across jobs/branches.
#
# Inputs (CI environment):
#   CI_REGISTRY_IMAGE, BUILD_IMAGE, TEST_IMAGE, APT_PROXY, CI, PIMELEON_PROFILE,
#   CACHE_IMAGE, BUILDKIT_INLINE_CACHE

# Prioritize local Dockerfiles if they exist in the branch root
BUILDER_DF="./containers/builder/Dockerfile"
TESTER_DF="./containers/tester/Dockerfile"
[ -f "$BUILDER_DF" ] || BUILDER_DF="./shared/containers/builder/Dockerfile"
[ -f "$TESTER_DF" ]  || TESTER_DF="./shared/containers/tester/Dockerfile"

echo "Using builder Dockerfile: ${BUILDER_DF}"
echo "Using tester Dockerfile: ${TESTER_DF}"

# Create BuildKit builder with docker-container driver (required for registry cache backend)
docker buildx create --use --driver docker-container

# Build builder image with BuildKit registry cache
echo "Building builder image..."
docker buildx build \
  --cache-from type=registry,ref="${CACHE_IMAGE}:builder-${CI_COMMIT_REF_SLUG}" \
  --cache-from type=registry,ref="${CACHE_IMAGE}:builder-main" \
  --cache-to type=registry,ref="${CACHE_IMAGE}:builder-${CI_COMMIT_REF_SLUG}",mode=max \
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

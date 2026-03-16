#!/bin/sh
set -eu
# Build and push builder/tester Docker images to the CI registry.
#
# Inputs (CI environment):
#   CI_REGISTRY_IMAGE, BUILD_IMAGE, TEST_IMAGE, APT_PROXY, CI, PIMELEON_PROFILE

# Prioritize local Dockerfiles if they exist in the branch root
BUILDER_DF="./containers/builder/Dockerfile"
TESTER_DF="./containers/tester/Dockerfile"
[ -f "$BUILDER_DF" ] || BUILDER_DF="./shared/containers/builder/Dockerfile"
[ -f "$TESTER_DF" ]  || TESTER_DF="./shared/containers/tester/Dockerfile"

echo "Using builder Dockerfile: ${BUILDER_DF}"
echo "Using tester Dockerfile: ${TESTER_DF}"

docker build --cache-from "${CI_REGISTRY_IMAGE}/builder:latest" \
  --build-arg APT_PROXY="${APT_PROXY:-}" \
  --build-arg CI="${CI:-}" \
  --build-arg PIMELEON_PROFILE="${PIMELEON_PROFILE:-}" \
  -t "$BUILD_IMAGE" -t "${CI_REGISTRY_IMAGE}/builder:latest" -f "$BUILDER_DF" .

docker build --cache-from "${CI_REGISTRY_IMAGE}/tester:latest" \
  --build-arg APT_PROXY="${APT_PROXY:-}" \
  --build-arg CI="${CI:-}" \
  --build-arg PIMELEON_PROFILE="${PIMELEON_PROFILE:-}" \
  -t "$TEST_IMAGE" -t "${CI_REGISTRY_IMAGE}/tester:latest" -f "$TESTER_DF" "$(dirname "$TESTER_DF")"

docker push --quiet "$BUILD_IMAGE"
docker push --quiet "${CI_REGISTRY_IMAGE}/builder:latest"
docker push --quiet "$TEST_IMAGE"
docker push --quiet "${CI_REGISTRY_IMAGE}/tester:latest"

#!/bin/sh
set -eu

if [ -z "${TEST_SUITE:-}" ]; then
    echo "[ERROR] TEST_SUITE environment variable is required (e.g. smoke or integration)"
    exit 1
fi

mkdir -p test-results

docker run --rm \
    --privileged \
    -v "$CI_PROJECT_DIR/output":/images:ro \
    -v "$CI_PROJECT_DIR/tests":/tests \
    -v "$CI_PROJECT_DIR/test-results":/results \
    -e TEST_SUITE="${TEST_SUITE}" \
    -e TARGET_PLATFORM="${TARGET_PLATFORM}" \
    "$TEST_IMAGE"

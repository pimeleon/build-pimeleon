#!/bin/sh
set -eu

# Re-evaluate BUILD_IMAGE to bypass GitLab CI rules variables bug
export BUILD_IMAGE="${CI_REGISTRY_IMAGE}/${BUILD_IMAGE_NAME}:${BUILD_IMAGE_TAG}"
export TEST_IMAGE="${CI_REGISTRY_IMAGE}/${TEST_IMAGE_NAME}:${TEST_IMAGE_TAG}"
echo "Checking registry for BUILD_IMAGE: ${BUILD_IMAGE}"
echo "Checking registry for TEST_IMAGE: ${TEST_IMAGE}"

if docker manifest inspect "${BUILD_IMAGE}" >/dev/null 2>&1; then
    echo "[INFO] Builder image FOUND in registry."
    BUILDER_FOUND=true
else
    echo "[WARN] Builder image MISSING from registry."
    BUILDER_FOUND=false
fi

if docker manifest inspect "${TEST_IMAGE}" >/dev/null 2>&1; then
    echo "[INFO] Tester image FOUND in registry."
    TESTER_FOUND=true
else
    echo "[WARN] Tester image MISSING from registry."
    TESTER_FOUND=false
fi

if [ "$BUILDER_FOUND" = true ] && [ "$TESTER_FOUND" = true ]; then
    echo "CONTAINERS_EXIST=true" >> containers.env
    echo "Builder and tester images already in registry — build will be skipped"
else
    echo "CONTAINERS_EXIST=false" >> containers.env
    echo "Images not found in registry — build required"
fi

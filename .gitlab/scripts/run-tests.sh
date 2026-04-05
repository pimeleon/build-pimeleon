#!/bin/sh
set -eu

apk add --no-cache curl git jq xz >/dev/null 2>&1 || true

if [ -z "${TEST_SUITE:-}" ]; then
    echo "[ERROR] TEST_SUITE environment variable is required (e.g. smoke or integration)"
    exit 1
fi

mkdir -p test-results
mkdir -p "$CI_PROJECT_DIR/output"

if [ -z "$(ls -A "$CI_PROJECT_DIR"/output/*.img 2>/dev/null)" ]; then
    if [ -n "$(ls -A "$CI_PROJECT_DIR"/output/*.img.xz 2>/dev/null)" ]; then
        echo "[INFO] Expanding existing compressed image artifact for tests"
        for archive in "$CI_PROJECT_DIR"/output/*.img.xz; do
            [ -f "$archive" ] || continue
            xz -dkf "$archive"
        done
    else
        if [ -n "${CI_COMMIT_TAG:-}" ]; then
            PACKAGE_VERSION="${CI_COMMIT_TAG}"
        else
            if [ -z "${PIMELEON_VERSION:-}" ]; then
                git fetch --tags --quiet 2>/dev/null || true
                PIMELEON_VERSION=$(sh ./shared/scripts/get-next-version.sh "${TARGET_PLATFORM}")
            fi
            PACKAGE_VERSION="${TARGET_PLATFORM}-v${PIMELEON_VERSION}"
        fi
        echo "[INFO] No local image artifact found. Trying registry package ${PACKAGE_VERSION}"
        if sh .gitlab/scripts/check-package-exists.sh "${PACKAGE_VERSION}"; then
            sh .gitlab/scripts/download-package-image.sh "${PACKAGE_VERSION}" "$CI_PROJECT_DIR/output"
            for archive in "$CI_PROJECT_DIR"/output/*.img.xz; do
                [ -f "$archive" ] || continue
                xz -dkf "$archive"
            done
        else
            status=$?
            if [ "${status}" -ne 1 ]; then
                exit "${status}"
            fi
        fi
    fi
fi

docker run --rm \
    --privileged \
    -v "$CI_PROJECT_DIR/output":/images:ro \
    -v "$CI_PROJECT_DIR/tests":/tests \
    -v "$CI_PROJECT_DIR/test-results":/results \
    -e TEST_SUITE="${TEST_SUITE}" \
    -e TARGET_PLATFORM="${TARGET_PLATFORM}" \
    "$TEST_IMAGE"

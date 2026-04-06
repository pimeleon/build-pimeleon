#!/bin/sh
set -eu

apk add --no-cache curl git jq xz >/dev/null 2>&1 || true

if [ -z "${TEST_SUITE:-}" ]; then
    echo "[ERROR] TEST_SUITE environment variable is required (e.g. smoke or integration)"
    exit 1
fi

mkdir -p test-results
mkdir -p "$CI_PROJECT_DIR/output"

if [ "${PIMELEON_ENABLE_TESTS:-0}" != "1" ]; then
    echo "[INFO] Tests are disabled. Set PIMELEON_ENABLE_TESTS=1 to run them."
    cat > test-results/junit.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites tests="0" failures="0" errors="0" skipped="1">
  <testsuite name="${TEST_SUITE}" tests="0" skipped="1">
    <testcase name="tests_disabled" classname="setup">
      <skipped message="Tests are disabled"/>
    </testcase>
  </testsuite>
</testsuites>
EOF
    exit 0
fi

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
            [ -n "${PIMELEON_VERSION:-}" ] || {
                echo "[ERROR] PIMELEON_VERSION is not set. Run .gitlab/scripts/detect-platform.sh first."
                exit 1
            }
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

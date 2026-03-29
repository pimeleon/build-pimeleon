#!/bin/bash
# Run Pimeleon integration tests
set -euo pipefail

TEST_SUITE="${TEST_SUITE:-integration}"
RESULTS_DIR="${TEST_RESULTS_DIR:-/results}"
IMAGES_DIR="${TEST_IMAGE_DIR:-/images}"

echo "=== Pimeleon Integration Tests ==="
echo "Test suite: ${TEST_SUITE}"
echo "Images dir: ${IMAGES_DIR}"
echo "Results dir: ${RESULTS_DIR}"

# Check for test images
if ! ls "${IMAGES_DIR}"/*.img 1>/dev/null 2>&1; then
    echo "ERROR: No .img files found in ${IMAGES_DIR}"
    echo "Skipping tests - no images to test"
    # Create empty JUnit report for CI
    cat > "${RESULTS_DIR}/junit.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites tests="0" failures="0" errors="0" skipped="1">
  <testsuite name="integration" tests="0" skipped="1">
    <testcase name="no_images" classname="setup">
      <skipped message="No images found to test"/>
    </testcase>
  </testsuite>
</testsuites>
EOF
    exit 0
fi

# List available images
echo ""
echo "Available images:"
ls -la "${IMAGES_DIR}"/*.img

# Run pytest if tests exist
if [[ -d /tests ]] && ls /tests/*.py 1>/dev/null 2>&1; then
    echo ""
    echo "Running pytest..."
    cd /tests
    pytest \
        --junitxml="${RESULTS_DIR}/junit.xml" \
        --timeout=300 \
        -v \
        .
else
    echo "No Python tests found in /tests"
    # Create placeholder JUnit report
    cat > "${RESULTS_DIR}/junit.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites tests="0" failures="0" errors="0" skipped="1">
  <testsuite name="integration" tests="0" skipped="1">
    <testcase name="no_tests" classname="setup">
      <skipped message="No test files found"/>
    </testcase>
  </testsuite>
</testsuites>
EOF
fi

echo ""
echo "=== Tests completed ==="

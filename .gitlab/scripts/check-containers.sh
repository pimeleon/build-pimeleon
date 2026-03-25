#!/bin/sh
set -eu

# Check builder and tester images using GitLab Registry API digests
# This is more reliable than 'docker manifest inspect' for skipping rebuilds.

# Inputs: BUILD_IMAGE, TEST_IMAGE, CI_API_V4_URL, CI_PROJECT_ID, CI_JOB_TOKEN

get_image_digest() {
    local full_image=$1
    # Extract path from image name (e.g., gitlab.pirouter.dev:5005/pimeleon/build-pimeleon/builder:release-rpi3-bookworm)
    # 1. Remove registry host
    local path_with_tag=$(echo "$full_image" | cut -d/ -f2-)
    # 2. Separate path and tag
    local path=$(echo "$path_with_tag" | cut -d: -f1)
    local tag=$(echo "$path_with_tag" | cut -d: -f2)

    # Encode path for API (slashes to %2F)
    local encoded_path=$(echo "$path" | sed 's/\//%2F/g')

    # Get Registry Repository ID
    local repo_id=$(curl -sk --header "JOB-TOKEN: $CI_JOB_TOKEN" \
        "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/registry/repositories" | \
        jq -r ".[] | select(.path==\"$path\") | .id")

    if [ -n "$repo_id" ]; then
        # Get Digest for Tag
        curl -sk --header "JOB-TOKEN: $CI_JOB_TOKEN" \
            "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/registry/repositories/${repo_id}/tags/${tag}" | \
            jq -r '.digest // empty'
    fi
}

BUILD_DIGEST=$(get_image_digest "$BUILD_IMAGE")
TEST_DIGEST=$(get_image_digest "$TEST_IMAGE")

if [ -n "$BUILD_DIGEST" ] && [ -n "$TEST_DIGEST" ]; then
    echo "CONTAINERS_EXIST=true" >> containers.env
    echo "BUILD_IMAGE_DIGEST=$BUILD_DIGEST" >> containers.env
    echo "TEST_IMAGE_DIGEST=$TEST_DIGEST" >> containers.env
    echo "Containers found in registry with stable digests. Build skipped."
else
    echo "CONTAINERS_EXIST=false" >> containers.env
    echo "Containers not found or incomplete in registry. Build required."
fi

#!/bin/sh
set -eu

# Check builder and tester images using GitLab Registry API digests
# Refactored according to: https://docs.gitlab.com/api/container_registry/

# Inputs: BUILD_IMAGE, TEST_IMAGE, CI_API_V4_URL, CI_PROJECT_ID, CI_JOB_TOKEN

get_image_digest() {
    local full_image=$1
    # Extract path and tag (e.g., gitlab.pirouter.dev:5005/pimeleon/build-pimeleon/builder:tag)
    local path_with_tag=$(echo "$full_image" | cut -d/ -f2-)
    local path=$(echo "$path_with_tag" | cut -d: -f1)
    local tag=$(echo "$path_with_tag" | cut -d: -f2)

    # 1. Find the repository ID for the image path
    # Using pagination to ensure we find the repo even in large projects
    local repo_id=""
    local page=1
    while [ -z "$repo_id" ]; do
        local resp=$(curl -sk --header "JOB-TOKEN: $CI_JOB_TOKEN" \
            "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/registry/repositories?page=${page}&per_page=50")

        if [ "$resp" = "[]" ] || [ -z "$resp" ]; then break; fi

        repo_id=$(echo "$resp" | jq -r ".[] | select(.path==\"$path\") | .id")
        [ -n "$repo_id" ] && break
        page=$((page + 1))
    done

    if [ -z "$repo_id" ]; then
        echo "Error: Repository path '$path' not found in project ${CI_PROJECT_ID}" >&2
        return 1
    fi

    # 2. Get the specific tag details to retrieve the immutable digest
    local tag_details=$(curl -sk --header "JOB-TOKEN: $CI_JOB_TOKEN" \
        "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/registry/repositories/${repo_id}/tags/${tag}")

    local digest=$(echo "$tag_details" | jq -r '.digest // empty')

    if [ -z "$digest" ]; then
        echo "Warning: Tag '$tag' not found for repository ID $repo_id" >&2
        return 1
    fi

    echo "$digest"
}

echo "Querying GitLab API for image digests..."

BUILD_DIGEST=$(get_image_digest "$BUILD_IMAGE" || echo "")
TEST_DIGEST=$(get_image_digest "$TEST_IMAGE" || echo "")

if [ -n "$BUILD_DIGEST" ] && [ -n "$TEST_DIGEST" ]; then
    echo "CONTAINERS_EXIST=true" >> containers.env
    echo "BUILD_IMAGE_DIGEST=$BUILD_DIGEST" >> containers.env
    echo "TEST_IMAGE_DIGEST=$TEST_DIGEST" >> containers.env
    echo "Success: Found stable digests in registry."
    echo "  Builder: $BUILD_DIGEST"
    echo "  Tester:  $TEST_DIGEST"
else
    echo "CONTAINERS_EXIST=false" >> containers.env
    echo "Notice: One or more containers missing from registry. Rebuild required."
fi

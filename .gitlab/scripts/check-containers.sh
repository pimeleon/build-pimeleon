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
    local repo_id=""
    local page=1
    while [ -z "$repo_id" ]; do
        local url="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/registry/repositories?page=${page}&per_page=50"
        local resp=$(curl -sk -w "\n%{http_code}" --header "JOB-TOKEN: $CI_JOB_TOKEN" "$url")
        local code=$(echo "$resp" | tail -1)
        local body=$(echo "$resp" | sed '$d')

        if [ "$code" != "200" ]; then
            echo "[ERROR] API request for repository list failed with HTTP $code" >&2
            echo "[DEBUG] URL: $url" >&2
            echo "[DEBUG] Response: $body" >&2
            return 1
        fi

        if [ "$body" = "[]" ] || [ -z "$body" ]; then break; fi

        repo_id=$(echo "$body" | jq -r ".[] | select(.path==\"$path\") | .id")
        [ -n "$repo_id" ] && [ "$repo_id" != "null" ] && break
        page=$((page + 1))
    done

    if [ -z "$repo_id" ] || [ "$repo_id" = "null" ]; then
        echo "[INFO] Repository path '$path' not found in registry." >&2
        return 1
    fi

    # 2. Get the specific tag details to retrieve the immutable digest
    local tag_url="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/registry/repositories/${repo_id}/tags/${tag}"
    local tag_resp=$(curl -sk -w "\n%{http_code}" --header "JOB-TOKEN: $CI_JOB_TOKEN" "$tag_url")
    local tag_code=$(echo "$tag_resp" | tail -1)
    local tag_body=$(echo "$tag_resp" | sed '$d')

    if [ "$tag_code" != "200" ]; then
        if [ "$tag_code" = "404" ]; then
            echo "[INFO] Tag '$tag' not found in registry for repository ID $repo_id." >&2
        else
            echo "[ERROR] API request for tag details failed with HTTP $tag_code" >&2
            echo "[DEBUG] URL: $tag_url" >&2
            echo "[DEBUG] Response: $tag_body" >&2
        fi
        return 1
    fi

    local digest=$(echo "$tag_body" | jq -r '.digest // empty')

    if [ -z "$digest" ] || [ "$digest" = "null" ]; then
        echo "[WARN] Digest not found in metadata for tag '$tag'." >&2
        return 1
    fi

    echo "$digest"
}

echo "[INFO] Querying GitLab API for image digests..."

BUILD_DIGEST=$(get_image_digest "$BUILD_IMAGE" || echo "")
TEST_DIGEST=$(get_image_digest "$TEST_IMAGE" || echo "")

if [ -n "$BUILD_DIGEST" ] && [ -n "$TEST_DIGEST" ]; then
    echo "CONTAINERS_EXIST=true" >> containers.env
    echo "BUILD_IMAGE_DIGEST=$BUILD_DIGEST" >> containers.env
    echo "TEST_IMAGE_DIGEST=$TEST_DIGEST" >> containers.env
    echo "[SUCCESS] Found stable digests in registry."
    echo "  Builder: $BUILD_DIGEST"
    echo "  Tester:  $TEST_DIGEST"
else
    echo "CONTAINERS_EXIST=false" >> containers.env
    echo "[INFO] One or more containers missing from registry. Build required."
fi

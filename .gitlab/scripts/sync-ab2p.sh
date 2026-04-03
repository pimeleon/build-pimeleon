#!/bin/sh
set -eu

# Install dependencies needed for registry checks and API requests
apk add --no-cache curl python3 >/dev/null 2>&1 || true

# Sync adblock2privoxy (AB2P) image and metadata between GitLab and GitHub.
# Handles build, push to GitLab, metadata generation, and sync to GitHub.
#
# Inputs (CI environment):
#   CI_REGISTRY_IMAGE, CI_JOB_TOKEN, CI_API_V4_URL, CI_PROJECT_ID, CI_COMMIT_SHA
#   GITHUB_REGISTRY_PUSH_TOKEN (PAT with packages:write scope)
#   FORCE_REBUILD (optional, set to "true" to force a fresh build)

AB2P_IMAGE_NAME="adblock2privoxy"
# Support local dev and various CI registry formats
REGISTRY_HOST="${CI_REGISTRY:-gitlab.pirouter.dev:5005}"

# Use authoritative GitLab CI variables for the image path
if [ -n "${CI_REGISTRY_IMAGE:-}" ]; then
    GL_IMAGE="${CI_REGISTRY_IMAGE}/${AB2P_IMAGE_NAME}:latest"
else
    # Local fallback
    PROJECT_PATH="${CI_PROJECT_PATH:-pimeleon/build-pimeleon}"
    GL_IMAGE="${REGISTRY_HOST}/${PROJECT_PATH}/${AB2P_IMAGE_NAME}:latest"
fi

GHCR_IMAGE="ghcr.io/pimeleon/build-pimeleon/${AB2P_IMAGE_NAME}:latest"
METADATA_PACKAGE_NAME="${AB2P_IMAGE_NAME}"
METADATA_VERSION="latest"

# 1. Check if image exists in GitLab registry and determine if build is needed
NEEDS_BUILD=false
if [ "${FORCE_REBUILD:-}" = "true" ]; then
    echo "[INFO] Force rebuild requested."
    NEEDS_BUILD=true
else
    echo "[INFO] Checking GitLab registry for ${AB2P_IMAGE_NAME}:latest via API..."
    # Always use GitLab API for the most authoritative check
    if [ -n "${CI_API_V4_URL:-}" ] && [ -n "${CI_PROJECT_ID:-}" ]; then
        # Fetch the registry repositories for the project
        REPOS_JSON=$(curl -s --header "JOB-TOKEN: ${CI_JOB_TOKEN}" "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/registry/repositories")

        # Find the ID for the adblock2privoxy repo
        REPO_ID=$(echo "${REPOS_JSON}" | python3 -c "import sys, json; print(next((r['id'] for r in json.load(sys.stdin) if r['name'] == '${AB2P_IMAGE_NAME}'), ''))")

        if [ -n "${REPO_ID}" ]; then
            # Check for the latest tag in that repo
            TAG_CHECK=$(curl -s --header "JOB-TOKEN: ${CI_JOB_TOKEN}" "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/registry/repositories/${REPO_ID}/tags/latest")
            if echo "${TAG_CHECK}" | grep -q '"name":"latest"'; then
                echo "[INFO] Image found in GitLab registry."
                # We FOUND it via API, but we MUST ensure the docker daemon can pull it
                echo "[INFO] Authenticating Docker daemon for registry access..."
                echo "$CI_JOB_TOKEN" | docker login "$REGISTRY_HOST" -u gitlab-ci-token --password-stdin
            else
                echo "[INFO] Image found in registry but 'latest' tag is missing."
                NEEDS_BUILD=true
            fi
        else
            echo "[INFO] adblock2privoxy repository not found in project registry."
            NEEDS_BUILD=true
        fi
    else
        # Fallback for local/non-CI environments
        if docker manifest inspect "${GL_IMAGE}" >/dev/null 2>&1; then
            echo "[INFO] Image found in GitLab registry (via manifest inspect)."
        else
            echo "[INFO] Image missing in GitLab registry."
            NEEDS_BUILD=true
        fi
    fi
fi
# 2. Build and push to GitLab if needed
if [ "${NEEDS_BUILD}" = "true" ]; then
    echo "[INFO] Building adblock2privoxy image..."
    AB2P_DF="./shared/containers/builder/Dockerfile.ab2p"
    [ -f "./containers/builder/Dockerfile.ab2p" ] && AB2P_DF="./containers/builder/Dockerfile.ab2p"

    BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    docker build \
        -t "${GL_IMAGE}" \
        --label "com.pimeleon.image=adblock2privoxy" \
        --label "com.pimeleon.build-date=${BUILD_DATE}" \
        --label "com.pimeleon.commit-sha=${CI_COMMIT_SHA}" \
        -f "${AB2P_DF}" "$(dirname "${AB2P_DF}")"

    echo "[INFO] Pushing image to GitLab Container Registry..."
    docker push "${GL_IMAGE}"

    # 3. Add metadata to GitLab Generic Packages registry
    echo "[INFO] Generating and uploading metadata to GitLab..."
    METADATA_FILE="adblock2privoxy.metadata.json"
    cat > "${METADATA_FILE}" <<EOF
{
    "image_name": "${AB2P_IMAGE_NAME}",
    "tag": "latest",
    "build_date": "${BUILD_DATE}",
    "commit_sha": "${CI_COMMIT_SHA}",
    "gitlab_image": "${GL_IMAGE}",
    "github_image": "${GHCR_IMAGE}"
}
EOF

    # Upload to Generic Packages registry
    HTTP_RESPONSE=$(curl -s -k -w "\n%{http_code}" \
        --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
        --upload-file "${METADATA_FILE}" \
        "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/${METADATA_PACKAGE_NAME}/${METADATA_VERSION}/${METADATA_FILE}")

    STATUS=$(echo "${HTTP_RESPONSE}" | tail -1)
    if [ "${STATUS}" != "201" ] && [ "${STATUS}" != "200" ]; then
        echo "[ERROR] Metadata upload failed with HTTP ${STATUS}"
        echo "[DEBUG] Response: $(echo "${HTTP_RESPONSE}" | sed '$d')"
        exit 1
    fi
    echo "[SUCCESS] Image and metadata pushed to GitLab."
else
    echo "[INFO] adblock2privoxy image already exists in GitLab registry. Skipping build."
    # Ensure we have the image locally for syncing to GitHub
    docker pull "${GL_IMAGE}"
fi

# 4. Check if image exists in GitHub registry
echo "[INFO] Checking GitHub Container Registry (GHCR)..."
if docker manifest inspect "${GHCR_IMAGE}" >/dev/null 2>&1 && [ "${FORCE_REBUILD:-}" != "true" ]; then
    echo "[INFO] Image already exists in GHCR. Sync complete."
else
    # 5. Upload to GitHub registry if missing
    if [ -z "${GITHUB_REGISTRY_PUSH_TOKEN:-}" ]; then
        echo "[WARN] GITHUB_REGISTRY_PUSH_TOKEN not set. Skipping GitHub sync."
    else
        echo "[INFO] Syncing image to GHCR..."
        echo "${GITHUB_REGISTRY_PUSH_TOKEN}" | docker login ghcr.io -u pimeleon --password-stdin
        docker tag "${GL_IMAGE}" "${GHCR_IMAGE}"
        docker push "${GHCR_IMAGE}"
        echo "[SUCCESS] Image synced to GHCR."
    fi
fi

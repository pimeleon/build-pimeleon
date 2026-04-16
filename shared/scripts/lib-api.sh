#!/bin/sh
# Shared API helpers for GitLab and GitHub REST calls.
# Source this file from scripts that need to make API requests.
#
# Required tools: curl, jq
#
# Simplified GitLab token handling:
#   GITLAB_FETCH_TOKEN  -> read access outside GitLab CI (PRIVATE-TOKEN)
#   CI_JOB_TOKEN        -> read access inside GitLab CI (JOB-TOKEN)
#   GITLAB_DEPLOY_TOKEN -> write/delete access (PRIVATE-TOKEN)
#
# Resolve base URL and project ID from environment at source time.
# CI_API_V4_URL / CI_PROJECT_ID are auto-injected by GitLab CI runners.
# GITLAB_API_V4_URL / GITLAB_PROJECT_ID are used in GitHub Actions and local builds.
GITLAB_API_URL="${CI_API_V4_URL:-${GITLAB_API_V4_URL:-}}"
GITLAB_PROJECT="${CI_PROJECT_ID:-${GITLAB_PROJECT_ID:-}}"
GITHUB_REPO="${GITHUB_REPO:-pimeleon/build-pimeleon}"

if [ -z "${GITLAB_API_URL:-}" ]; then echo "[WARN] lib-api.sh: GITLAB_API_URL not set" >&2; fi
if [ -z "${GITLAB_PROJECT:-}" ]; then echo "[WARN] lib-api.sh: GITLAB_PROJECT not set" >&2; fi

# ---------------------------------------------------------------------------
# GitLab API GET
# Usage: gitlab_api_get <path>
# Prints JSON body to stdout; exits non-zero on HTTP error or auth failure.
# ---------------------------------------------------------------------------
gitlab_api_get() {
    _ga_path="$1"
    command -v curl >/dev/null 2>&1 || { echo "[ERROR] curl is required" >&2; return 1; }

    if [ -n "${GITLAB_FETCH_TOKEN:-}" ]; then
        _ga_raw=$(curl -sk -w "\n%{http_code}" \
            -H "PRIVATE-TOKEN: ${GITLAB_FETCH_TOKEN}" \
            "${GITLAB_API_URL}${_ga_path}" 2>/dev/null)
    elif [ -n "${CI_JOB_TOKEN:-}" ]; then
        _ga_raw=$(curl -sk -w "\n%{http_code}" \
            -H "JOB-TOKEN: ${CI_JOB_TOKEN}" \
            "${GITLAB_API_URL}${_ga_path}" 2>/dev/null)
    else
        echo "[ERROR] No GitLab auth token (GITLAB_FETCH_TOKEN / CI_JOB_TOKEN)" >&2
        return 1
    fi

    _ga_status=$(printf '%s' "$_ga_raw" | tail -1)
    _ga_body=$(printf '%s' "$_ga_raw" | sed '$d')

    if [ "$_ga_status" != "200" ]; then
        echo "[ERROR] GitLab API GET ${_ga_path}: HTTP ${_ga_status}" >&2
        echo "[DEBUG] Response: ${_ga_body}" >&2
        return 1
    fi

    printf '%s' "$_ga_body"
}

# ---------------------------------------------------------------------------
# GitLab API PUT (file upload)
# Usage: gitlab_api_put <path> <file>
# Prefers CI_JOB_TOKEN (JOB-TOKEN) in CI; falls back to GITLAB_DEPLOY_TOKEN.
# ---------------------------------------------------------------------------
gitlab_api_put() {
    _gp_path="$1"
    _gp_file="$2"
    command -v curl >/dev/null 2>&1 || { echo "[ERROR] curl is required" >&2; return 1; }

    if [ -n "${CI_JOB_TOKEN:-}" ]; then
        _gp_raw=$(curl -sk -w "\n%{http_code}" \
            -H "JOB-TOKEN: ${CI_JOB_TOKEN}" \
            --upload-file "$_gp_file" \
            "${GITLAB_API_URL}${_gp_path}" 2>/dev/null)
    elif [ -n "${GITLAB_DEPLOY_TOKEN:-}" ]; then
        _gp_raw=$(curl -sk -w "\n%{http_code}" \
            -H "PRIVATE-TOKEN: ${GITLAB_DEPLOY_TOKEN}" \
            --upload-file "$_gp_file" \
            "${GITLAB_API_URL}${_gp_path}" 2>/dev/null)
    else
        echo "[ERROR] No write token available (CI_JOB_TOKEN / GITLAB_DEPLOY_TOKEN)" >&2
        return 1
    fi

    _gp_status=$(printf '%s' "$_gp_raw" | tail -1)
    _gp_body=$(printf '%s' "$_gp_raw" | sed '$d')

    if [ "$_gp_status" != "200" ] && [ "$_gp_status" != "201" ]; then
        echo "[ERROR] GitLab API PUT ${_gp_path}: HTTP ${_gp_status}" >&2
        echo "[DEBUG] Response: ${_gp_body}" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# GitLab API DELETE
# Usage: gitlab_api_delete <path>
# Prefers CI_JOB_TOKEN (JOB-TOKEN) in CI; falls back to GITLAB_DEPLOY_TOKEN.
# ---------------------------------------------------------------------------
gitlab_api_delete() {
    _gd_path="$1"
    command -v curl >/dev/null 2>&1 || { echo "[ERROR] curl is required" >&2; return 1; }

    if [ -n "${CI_JOB_TOKEN:-}" ]; then
        _gd_raw=$(curl -sk -X DELETE -w "\n%{http_code}" \
            -H "JOB-TOKEN: ${CI_JOB_TOKEN}" \
            "${GITLAB_API_URL}${_gd_path}" 2>/dev/null)
    elif [ -n "${GITLAB_DEPLOY_TOKEN:-}" ]; then
        _gd_raw=$(curl -sk -X DELETE -w "\n%{http_code}" \
            -H "PRIVATE-TOKEN: ${GITLAB_DEPLOY_TOKEN}" \
            "${GITLAB_API_URL}${_gd_path}" 2>/dev/null)
    else
        echo "[ERROR] No write token available (CI_JOB_TOKEN / GITLAB_DEPLOY_TOKEN)" >&2
        return 1
    fi

    _gd_status=$(printf '%s' "$_gd_raw" | tail -1)
    _gd_body=$(printf '%s' "$_gd_raw" | sed '$d')

    if [ "$_gd_status" != "200" ] && [ "$_gd_status" != "204" ]; then
        echo "[ERROR] GitLab API DELETE ${_gd_path}: HTTP ${_gd_status}" >&2
        echo "[DEBUG] Response: ${_gd_body}" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# GitLab generic package download
# Usage: gitlab_download <url> <output_file>
# ---------------------------------------------------------------------------
gitlab_download() {
    _gd_url="$1"
    _gd_out="$2"
    command -v curl >/dev/null 2>&1 || { echo "[ERROR] curl is required" >&2; return 1; }

    if [ -n "${GITLAB_FETCH_TOKEN:-}" ]; then
        curl -sk --fail -H "PRIVATE-TOKEN: ${GITLAB_FETCH_TOKEN}" -o "$_gd_out" "$_gd_url" || return 1
    elif [ -n "${CI_JOB_TOKEN:-}" ]; then
        curl -sk --fail -H "JOB-TOKEN: ${CI_JOB_TOKEN}" -o "$_gd_out" "$_gd_url" || return 1
    else
        echo "[ERROR] No GitLab auth token available for download (GITLAB_FETCH_TOKEN / CI_JOB_TOKEN)" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# GitHub API GET
# Usage: github_api_get <path>
# Prints JSON body to stdout; exits non-zero on failure.
# ---------------------------------------------------------------------------
github_api_get() {
    _gh_path="$1"
    _gh_token="${GITHUB_REGISTRY_PUSH_TOKEN:-${GITHUB_TOKEN:-}}"
    command -v curl >/dev/null 2>&1 || { echo "[ERROR] curl is required" >&2; return 1; }

    if [ -n "$_gh_token" ]; then
        curl -sf \
            -H "Authorization: Bearer ${_gh_token}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com${_gh_path}" 2>/dev/null || return 1
    else
        curl -sf \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com${_gh_path}" 2>/dev/null || return 1
    fi
}

# ---------------------------------------------------------------------------
# Resolve GitLab package ID for a given package version string.
# Usage: gitlab_package_id <package_version>
# Prints numeric package ID to stdout; exits non-zero if not found.
# ---------------------------------------------------------------------------
gitlab_package_id() {
    _pkv="$1"
    command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq is required" >&2; return 1; }
    _pkv_body=$(gitlab_api_get \
        "/projects/${GITLAB_PROJECT}/packages?package_name=pimeleon&package_version=${_pkv}") || return 1
    _pkv_id=$(printf '%s' "$_pkv_body" | \
        jq -r --arg v "$_pkv" 'first(.[] | select(.version == $v) | .id | tostring) // empty' 2>/dev/null)
    [ -n "$_pkv_id" ] || { echo "[ERROR] Package ${_pkv} not found in registry" >&2; return 1; }
    printf '%s' "$_pkv_id"
}
